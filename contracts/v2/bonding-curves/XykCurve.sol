// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICurve} from "./ICurve.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {LSSVMPair} from "../LSSVMPair.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LSSVMPairCloner} from "../lib/LSSVMPairCloner.sol";
import {LSSVMPairERC20} from "../LSSVMPairERC20.sol";
import {ILSSVMPairFactoryLike} from "../LSSVMPairFactory.sol";

/*
    @author 0xacedia
    @notice Bonding curve logic for an x*y=k curve using virtual reserves.
    @dev    The virtual token reserve is stored in `spotPrice` and the virtual nft reserve is stored in `delta`.
            An LP can modify the virtual reserves by changing the `spotPrice` (tokens) or `delta` (nfts).
*/
contract XykCurve is ICurve, CurveErrorCodes {
    using FixedPointMathLib for uint256;

    /**
        @dev See {ICurve-validateDelta}
     */
    function validateDelta(uint128 delta)
        external
        pure
        override
        returns (bool)
    {
        // all values are valid
        return true;
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
        // all values are valid
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
        if (param.numItems == 0) {
            return result;
        }

        // get the pair's virtual nft and eth/erc20 reserves
        uint256 tokenBalance = param.spotPrice;
        uint256 nftBalance = param.delta;

        // If numItems is too large, we will get divide by zero error
        if (param.numItems >= nftBalance) {
            return result;
        }

        // calculate the amount to send in
        uint256 inputValueWithoutFee = (param.numItems * tokenBalance) /
            (nftBalance - param.numItems);

        // add the fees to the amount to send in
        result.protocolFee = inputValueWithoutFee.fmul(
            param.protocolFeeMultiplier,
            FixedPointMathLib.WAD
        );
        uint256 fee = inputValueWithoutFee.fmul(
            param.feeMultiplier,
            FixedPointMathLib.WAD
        );

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
        
        result.inputValue = inputValueWithoutFee + fee + result.protocolFee;

        for (uint256 i = 0; i < result.operatorProtocolFees.length; ) {
            result.inputValue += result.operatorProtocolFees[i];

            unchecked {
                ++i;
            }
        }

        // set the new virtual reserves
        result.newSpotPrice = uint128(param.spotPrice + inputValueWithoutFee); // token reserve
        result.newDelta = uint128(nftBalance - param.numItems); // nft reserve

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
        if (param.numItems == 0) {
            return result;
        }

        // get the pair's virtual nft and eth/erc20 balance
        uint256 tokenBalance = param.spotPrice;
        uint256 nftBalance = param.delta;

        // calculate the amount to send out
        uint256 outputValueWithoutFee = (param.numItems * tokenBalance) /
            (nftBalance + param.numItems);

        // subtract fees from amount to send out
        result.protocolFee = outputValueWithoutFee.fmul(
            param.protocolFeeMultiplier,
            FixedPointMathLib.WAD
        );
        uint256 fee = outputValueWithoutFee.fmul(
            param.feeMultiplier,
            FixedPointMathLib.WAD
        );

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

        result.outputValue = outputValueWithoutFee - fee - result.protocolFee;

        for (uint256 i = 0; i < result.operatorProtocolFees.length; ) {
            result.outputValue -= result.operatorProtocolFees[i];
            unchecked {
                ++i;
            }
        }

        // set the new virtual reserves
        result.newSpotPrice = uint128(param.spotPrice - outputValueWithoutFee); // token reserve
        result.newDelta = uint128(nftBalance + param.numItems); // nft reserve

        // If we got all the way here, no math error happened
        result.error = Error.OK;
    }
}