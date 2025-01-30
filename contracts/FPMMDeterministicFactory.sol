// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ConditionalTokens} from "@lay3rlabs/conditional-tokens-contracts/ConditionalTokens.sol";
import {CTHelpers} from "@lay3rlabs/conditional-tokens-contracts/CTHelpers.sol";
import {FixedProductMarketMaker} from "./FixedProductMarketMaker.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract FPMMDeterministicFactory is IERC1155Receiver {
    event FixedProductMarketMakerCreation(
        address indexed creator,
        FixedProductMarketMaker fixedProductMarketMaker,
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] conditionIds,
        uint256 fee
    );

    FixedProductMarketMaker public implementationMaster;
    address internal currentFunder;

    constructor() {
        implementationMaster = new FixedProductMarketMaker();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4)
    {
        ConditionalTokens(msg.sender).safeTransferFrom(address(this), currentFunder, id, value, data);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        ConditionalTokens(msg.sender).safeBatchTransferFrom(address(this), currentFunder, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    function create2FixedProductMarketMaker(
        bytes32 salt,
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] calldata conditionIds,
        uint256 fee,
        uint256 initialFunds,
        uint256[] calldata distributionHint
    ) external returns (FixedProductMarketMaker fixedProductMarketMaker) {
        fixedProductMarketMaker =
            FixedProductMarketMaker(Clones.cloneDeterministic(address(implementationMaster), salt));
        fixedProductMarketMaker.initialize(conditionalTokens, collateralToken, conditionIds, fee);

        emit FixedProductMarketMakerCreation(
            msg.sender, fixedProductMarketMaker, conditionalTokens, collateralToken, conditionIds, fee
        );

        if (initialFunds > 0) {
            currentFunder = msg.sender;

            // Transfer funding to this factory
            collateralToken.transferFrom(msg.sender, address(this), initialFunds);

            // Approve the market maker to spend the funding from this factory
            collateralToken.approve(address(fixedProductMarketMaker), initialFunds);

            // Add funding to the market maker, which will spend the funds from this factory
            fixedProductMarketMaker.addFunding(initialFunds, distributionHint);

            // Transfer the outcome tokens to the creator
            fixedProductMarketMaker.transfer(msg.sender, fixedProductMarketMaker.balanceOf(address(this)));

            currentFunder = address(0);
        }

        return fixedProductMarketMaker;
    }
}
