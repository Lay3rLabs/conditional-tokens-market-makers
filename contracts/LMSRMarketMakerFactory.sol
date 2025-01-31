// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import {LMSRMarketMaker} from "./LMSRMarketMaker.sol";
import {Whitelist} from "./Whitelist.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ConditionalTokens} from "@lay3rlabs/conditional-tokens-contracts/ConditionalTokens.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract LMSRMarketMakerFactory {
    event LMSRMarketMakerCreation(
        address indexed creator,
        LMSRMarketMaker lmsrMarketMaker,
        ConditionalTokens pmSystem,
        IERC20 collateralToken,
        bytes32[] conditionIds,
        uint64 fee,
        uint256 funding
    );

    LMSRMarketMaker public implementationMaster;

    constructor() {
        implementationMaster = new LMSRMarketMaker(address(this));
    }

    function createLMSRMarketMaker(
        ConditionalTokens pmSystem,
        IERC20 collateralToken,
        bytes32[] calldata conditionIds,
        uint64 fee,
        Whitelist whitelist,
        uint256 funding
    ) external returns (LMSRMarketMaker lmsrMarketMaker) {
        lmsrMarketMaker = LMSRMarketMaker(Clones.clone(address(implementationMaster)));
        lmsrMarketMaker.initialize(pmSystem, collateralToken, conditionIds, fee, whitelist);

        // Transfer funding to this factory
        collateralToken.transferFrom(msg.sender, address(this), funding);

        // Approve the market maker to spend the funding from this factory
        collateralToken.approve(address(lmsrMarketMaker), funding);

        // Add funding to the market maker, which will spend the funds from this factory
        lmsrMarketMaker.changeFunding(int256(funding));

        // Resume the market maker
        lmsrMarketMaker.resume();

        // Transfer ownership to the creator
        lmsrMarketMaker.transferOwnership(msg.sender);

        emit LMSRMarketMakerCreation(msg.sender, lmsrMarketMaker, pmSystem, collateralToken, conditionIds, fee, funding);
    }
}
