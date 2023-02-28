// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICurve} from "./ICurve.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

/*
    @author 0xmons and boredGenius
    @notice Bonding curve logic for a linear curve, where each buy/sell changes spot price by adding/substracting delta
*/
contract LinearCurve is ICurve, CurveErrorCodes {
    using FixedPointMathLib for uint256;

    /**
        @dev See {ICurve-validateDelta}
     */
    function validateDelta(
        uint128 /*delta*/
    ) external pure override returns (bool valid) {
        // For a linear curve, all values of delta are valid
        return true;
    }

    /**
        @dev See {ICurve-validateSpotPrice}
     */
    function validateSpotPrice(
        uint128 /* newSpotPrice */
    ) external pure override returns (bool) {
        // For a linear curve, all values of spot price are valid
        return true;
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
        // We only calculate changes for buying 1 or more NFTs
        if (param.numItems == 0) {
            return result;
        }

        // For a linear curve, the spot price increases by delta for each item bought
        uint256 newSpotPrice_ = param.spotPrice + param.delta * param.numItems;
        if (newSpotPrice_ > type(uint128).max) {
            result.error = Error.SPOT_PRICE_OVERFLOW;
            return result;
        }
        result.newSpotPrice = uint128(newSpotPrice_);

        // Spot price is assumed to be the instant sell price. To avoid arbitraging LPs, we adjust the buy price upwards.
        // If spot price for buy and sell were the same, then someone could buy 1 NFT and then sell for immediate profit.
        // EX: Let S be spot price. Then buying 1 NFT costs S ETH, now new spot price is (S+delta).
        // The same person could then sell for (S+delta) ETH, netting them delta ETH profit.
        // If spot price for buy and sell differ by delta, then buying costs (S+delta) ETH.
        // The new spot price would become (S+delta), so selling would also yield (S+delta) ETH.
        uint256 buySpotPrice = param.spotPrice + param.delta;

        // If we buy n items, then the total cost is equal to:
        // (buy spot price) + (buy spot price + 1*delta) + (buy spot price + 2*delta) + ... + (buy spot price + (n-1)*delta)
        // This is equal to n*(buy spot price) + (delta)*(n*(n-1))/2
        // because we have n instances of buy spot price, and then we sum up from delta to (n-1)*delta
        result.inputValue =
            param.numItems *
            buySpotPrice +
            (param.numItems * (param.numItems - 1) * param.delta) /
            2;

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
        // We only calculate changes for selling 1 or more NFTs
        if (param.numItems == 0) {
            return result;
        }

        // We first calculate the change in spot price after selling all of the items
        uint256 totalPriceDecrease = param.delta * param.numItems;

        // If the current spot price is less than the total amount that the spot price should change by...
        if (param.spotPrice < totalPriceDecrease) {
            // Then we set the new spot price to be 0. (Spot price is never negative)
            result.newSpotPrice = 0;

            // We calculate how many items we can sell into the linear curve until the spot price reaches 0, rounding up
            uint256 numItemsTillZeroPrice = param.spotPrice / param.delta + 1;
            param.numItems = numItemsTillZeroPrice;
        }
        // Otherwise, the current spot price is greater than or equal to the total amount that the spot price changes
        // Thus we don't need to calculate the maximum number of items until we reach zero spot price, so we don't modify numItems
        else {
            // The new spot price is just the change between spot price and the total price change
            result.newSpotPrice = param.spotPrice - uint128(totalPriceDecrease);
        }

        // If we sell n items, then the total sale amount is:
        // (spot price) + (spot price - 1*delta) + (spot price - 2*delta) + ... + (spot price - (n-1)*delta)
        // This is equal to n*(spot price) - (delta)*(n*(n-1))/2
        result.outputValue =
            param.numItems *
            param.spotPrice -
            (param.numItems * (param.numItems - 1) * param.delta) /
            2;

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

        // Subtract the protocol fee from the output amount to the seller
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

        // If we reached here, no math errors
        result.error = Error.OK;
    }
}