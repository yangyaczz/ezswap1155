// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

contract CurveErrorCodes {
    enum Error {
        OK, // No error
        INVALID_NUMITEMS, // The numItem value is 0
        SPOT_PRICE_OVERFLOW // The updated spot price doesn't fit into 128 bits
    }

    /**
        @param spotPrice The current selling spot price of the pair, in tokens
        @param delta The delta parameter of the pair, what it means depends on the curve
        @param numItems The number of NFTs the user is buying from the pair
        @param feeMultiplier Determines how much fee the LP takes from this trade, 18 decimals
        @param protocolFeeMultiplier Determines how much fee the protocol takes from this trade, 18 decimals
        @param operatorProtocolFeeMultiplier Determines how much fee the operator takes from this trade, 18 decimals
    */
    struct BuyParam {
        uint128 spotPrice;
        uint128 delta;
        uint256 numItems;
        uint256 feeMultiplier;
        uint256 protocolFeeMultiplier;
        uint256[] operatorProtocolFeeMultipliers;
    }

    /**
        @return error Any math calculation errors, only Error.OK means the returned values are valid
        @return newSpotPrice The updated selling spot price, in tokens
        @return newDelta The updated delta, used to parameterize the bonding curve
        @return inputValue The amount that the user should pay, in tokens
        @return protocolFee The amount of fee to send to the protocol, in tokens
    */
    struct BuyResult {
        CurveErrorCodes.Error error;
        uint128 newSpotPrice;
        uint128 newDelta;
        uint256 inputValue;
        uint256 protocolFee;
        uint256[] operatorProtocolFees;
    }

    /**
        @param spotPrice The current selling spot price of the pair, in tokens
        @param delta The delta parameter of the pair, what it means depends on the curve
        @param numItems The number of NFTs the user is buying from the pair
        @param feeMultiplier Determines how much fee the LP takes from this trade, 18 decimals
        @param protocolFeeMultiplier Determines how much fee the protocol takes from this trade, 18 decimals
        @param operatorProtocolFeeMultiplier Determines how much fee the operator takes from this trade, 18 decimals
    */
    struct SellParam {
        uint128 spotPrice;
        uint128 delta;
        uint256 numItems;
        uint256 feeMultiplier;
        uint256 protocolFeeMultiplier;
        uint256[] operatorProtocolFeeMultipliers;
    }

    /**
        @return error Any math calculation errors, only Error.OK means the returned values are valid
        @return newSpotPrice The updated selling spot price, in tokens
        @return newDelta The updated delta, used to parameterize the bonding curve
        @return outputValue The amount that the user should receive, in tokens
        @return protocolFee The amount of fee to send to the protocol, in tokens
     */
    struct SellResult {
        CurveErrorCodes.Error error;
        uint128 newSpotPrice;
        uint128 newDelta;
        uint256 outputValue;
        uint256 protocolFee;
        uint256[] operatorProtocolFees;
    }
}
