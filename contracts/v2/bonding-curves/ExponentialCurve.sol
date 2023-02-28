// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICurve} from "./ICurve.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

/*
    @author 0xmons and boredGenius
    @notice Bonding curve logic for an exponential curve, where each buy/sell changes spot price by multiplying/dividing delta
*/
contract ExponentialCurve is ICurve, CurveErrorCodes {
    using FixedPointMathLib for uint256;

    // minimum price to prevent numerical issues
    uint256 public constant MIN_PRICE = 1 gwei;

    /**
        @dev See {ICurve-validateDelta}
     */
    function validateDelta(uint128 delta)
        external
        pure
        override
        returns (bool)
    {
        return delta > FixedPointMathLib.WAD;
    }

    /**
        @dev See {ICurve-validateSpotPrice}
     */
    function validateSpotPrice(uint128 newSpotPrice)
        external
        pure
        override
        returns (bool)
    {
        return newSpotPrice >= MIN_PRICE;
    }

    /**
        @dev See {ICurve-getBuyInfo}
     */
    function getBuyInfo(
        CurveErrorCodes.BuyParam memory param
    )
        external
        pure
        override
        returns (
            CurveErrorCodes.BuyResult memory result
        )
    {
        // NOTE: we assume delta is > 1, as checked by validateDelta()
        // We only calculate changes for buying 1 or more NFTs
        if (param.numItems == 0) {
            return result;
        }

        uint256 deltaPowN = uint256(param.delta).fpow(
            param.numItems,
            FixedPointMathLib.WAD
        );

        // For an exponential curve, the spot price is multiplied by delta for each item bought
        uint256 newSpotPrice_ = uint256(param.spotPrice).fmul(
            deltaPowN,
            FixedPointMathLib.WAD
        );
        if (newSpotPrice_ > type(uint128).max) {
            result.error = Error.SPOT_PRICE_OVERFLOW;
            return result;
        }
        result.newSpotPrice = uint128(newSpotPrice_);

        // Spot price is assumed to be the instant sell price. To avoid arbitraging LPs, we adjust the buy price upwards.
        // If spot price for buy and sell were the same, then someone could buy 1 NFT and then sell for immediate profit.
        // EX: Let S be spot price. Then buying 1 NFT costs S ETH, now new spot price is (S * delta).
        // The same person could then sell for (S * delta) ETH, netting them delta ETH profit.
        // If spot price for buy and sell differ by delta, then buying costs (S * delta) ETH.
        // The new spot price would become (S * delta), so selling would also yield (S * delta) ETH.
        uint256 buySpotPrice = uint256(param.spotPrice).fmul(
            param.delta,
            FixedPointMathLib.WAD
        );

        // If the user buys n items, then the total cost is equal to:
        // buySpotPrice + (delta * buySpotPrice) + (delta^2 * buySpotPrice) + ... (delta^(numItems - 1) * buySpotPrice)
        // This is equal to buySpotPrice * (delta^n - 1) / (delta - 1)
        result.inputValue = buySpotPrice.fmul(
            (deltaPowN - FixedPointMathLib.WAD).fdiv(
                param.delta - FixedPointMathLib.WAD,
                FixedPointMathLib.WAD
            ),
            FixedPointMathLib.WAD
        );

        // Account for the protocol fee, a flat percentage of the buy amount
        result.protocolFee = result.inputValue.fmul(
            param.protocolFeeMultiplier,
            FixedPointMathLib.WAD
        );

        // Account for the operator protocol fee, a flat percentage of the buy amount

        result.operatorProtocolFees = new uint256[](param.operatorProtocolFeeMultipliers.length);

        for (uint256 i = 0; i < result.operatorProtocolFees.length; ) {
            result.operatorProtocolFees[i] = result.inputValue.fmul(
                param.operatorProtocolFeeMultipliers[i],
                FixedPointMathLib.WAD
            );

            unchecked {
                ++i;
            }
        }
        

        // Account for the trade fee, only for Trade pools
        result.inputValue += result.inputValue.fmul(param.feeMultiplier, FixedPointMathLib.WAD);

        // Add the protocol fee to the required input amount
        result.inputValue += result.protocolFee;

        // Add the operator protocol fee to the required input amount
        for (uint256 i = 0; i < result.operatorProtocolFees.length; ) {
            result.inputValue += result.operatorProtocolFees[i];

            unchecked {
                ++i;
            }
        }

        // Keep delta the same
        result.newDelta = param.delta;

        // If we got all the way here, no math error happened
        result.error = Error.OK;
    }

    /**
        @dev See {ICurve-getSellInfo}
        If newSpotPrice is less than MIN_PRICE, newSpotPrice is set to MIN_PRICE instead.
        This is to prevent the spot price from ever becoming 0, which would decouple the price
        from the bonding curve (since 0 * delta is still 0)
     */
    function getSellInfo(
        CurveErrorCodes.SellParam memory param
    )
        external
        pure
        override
        returns (
            CurveErrorCodes.SellResult memory result
        )
    {
        // NOTE: we assume delta is > 1, as checked by validateDelta()

        // We only calculate changes for buying 1 or more NFTs
        if (param.numItems == 0) {
            return result;
        }

        uint256 invDelta = FixedPointMathLib.WAD.fdiv(
            param.delta,
            FixedPointMathLib.WAD
        );
        uint256 invDeltaPowN = invDelta.fpow(param.numItems, FixedPointMathLib.WAD);

        // For an exponential curve, the spot price is divided by delta for each item sold
        // safe to convert newSpotPrice directly into uint128 since we know newSpotPrice <= spotPrice
        // and spotPrice <= type(uint128).max
        result.newSpotPrice = uint128(
            uint256(param.spotPrice).fmul(invDeltaPowN, FixedPointMathLib.WAD)
        );
        if (result.newSpotPrice < MIN_PRICE) {
            result.newSpotPrice = uint128(MIN_PRICE);
        }

        // If the user sells n items, then the total revenue is equal to:
        // spotPrice + ((1 / delta) * spotPrice) + ((1 / delta)^2 * spotPrice) + ... ((1 / delta)^(numItems - 1) * spotPrice)
        // This is equal to spotPrice * (1 - (1 / delta^n)) / (1 - (1 / delta))
        result.outputValue = uint256(param.spotPrice).fmul(
            (FixedPointMathLib.WAD - invDeltaPowN).fdiv(
                FixedPointMathLib.WAD - invDelta,
                FixedPointMathLib.WAD
            ),
            FixedPointMathLib.WAD
        );

        // Account for the protocol fee, a flat percentage of the sell amount
        result.protocolFee = result.outputValue.fmul(
            param.protocolFeeMultiplier,
            FixedPointMathLib.WAD
        );

        // Account for the operator protocol fee, a flat percentage of the sell amount
        result.operatorProtocolFees = new uint256[](param.operatorProtocolFeeMultipliers.length);

        for (uint256 i = 0; i < result.operatorProtocolFees.length; ) {
            result.operatorProtocolFees[i] = result.outputValue.fmul(
                param.operatorProtocolFeeMultipliers[i],
                FixedPointMathLib.WAD
            );

            unchecked {
                ++i;
            }
        }

        // Account for the trade fee, only for Trade pools
        result.outputValue -= result.outputValue.fmul(param.feeMultiplier, FixedPointMathLib.WAD);

        // Remove the protocol fee from the output amount
        result.outputValue -= result.protocolFee;

        // Remove the protocol fee from the output amount
        for (uint256 i = 0; i < result.operatorProtocolFees.length; ) {
            result.outputValue -= result.operatorProtocolFees[i];
            unchecked {
                ++i;
            }
        }

        // Keep delta the same
        result.newDelta = param.delta;

        // If we got all the way here, no math error happened
        result.error = Error.OK;
    }
}