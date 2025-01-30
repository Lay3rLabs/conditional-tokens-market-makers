// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ConditionalTokens} from "@lay3rlabs/conditional-tokens-contracts/ConditionalTokens.sol";
import {CTHelpers} from "@lay3rlabs/conditional-tokens-contracts/CTHelpers.sol";
import {FixedProductMarketMaker} from "./FixedProductMarketMaker.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract FixedProductMarketMakerFactory {
    event FixedProductMarketMakerCreation(
        address indexed creator,
        FixedProductMarketMaker fixedProductMarketMaker,
        ConditionalTokens indexed conditionalTokens,
        IERC20 indexed collateralToken,
        bytes32[] conditionIds,
        uint256 fee
    );

    FixedProductMarketMaker public implementationMaster;

    constructor() {
        implementationMaster = new FixedProductMarketMaker();
    }

    function createFixedProductMarketMaker(
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] calldata conditionIds,
        uint256 fee
    ) external returns (FixedProductMarketMaker fixedProductMarketMaker) {
        fixedProductMarketMaker = FixedProductMarketMaker(
            Clones.clone(address(implementationMaster))
        );
        fixedProductMarketMaker.initialize(
            conditionalTokens,
            collateralToken,
            conditionIds,
            fee
        );

        emit FixedProductMarketMakerCreation(
            msg.sender,
            fixedProductMarketMaker,
            conditionalTokens,
            collateralToken,
            conditionIds,
            fee
        );
    }
}
