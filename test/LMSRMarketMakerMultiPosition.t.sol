// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {LMSRMarketMakerFactory} from "../contracts/LMSRMarketMakerFactory.sol";
import {LMSRMarketMaker} from "../contracts/LMSRMarketMaker.sol";
import {ERC20Mintable} from "./ERC20Mintable.sol";
import {Whitelist} from "../contracts/Whitelist.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalTokens} from "@lay3rlabs/conditional-tokens-contracts/ConditionalTokens.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract LMSRMarketMakerMultiPositionTests is Test {
    ConditionalTokens public conditionalTokens;
    LMSRMarketMakerFactory public lmsrMarketMakerFactory;
    LMSRMarketMaker public lmsrMarketMaker;
    ERC20Mintable public collateralToken;
    Whitelist public whitelist;

    bytes32 public constant NULL_BYTES32 = bytes32(0);
    uint256 public constant FUNDING = 1e17;

    address public LMSR_OWNER = vm.addr(1);
    address public ORACLE1 = vm.addr(2);
    address public ORACLE2 = vm.addr(3);
    address public TRADER = vm.addr(4);

    bytes32 public questionId1;
    bytes32 public questionId2;
    bytes32 public conditionId1;
    bytes32 public conditionId2;
    uint256 public positionId1;
    uint256 public positionId2;
    uint256 public positionId3;
    uint256 public positionId4;

    function setUp() public virtual {
        conditionalTokens = new ConditionalTokens("");
        lmsrMarketMakerFactory = new LMSRMarketMakerFactory();
        collateralToken = new ERC20Mintable();
        whitelist = new Whitelist(LMSR_OWNER);

        address[] memory users = new address[](1);
        users[0] = TRADER;
        vm.prank(LMSR_OWNER);
        whitelist.addToWhitelist(users);

        questionId1 = keccak256(abi.encodePacked("question1"));
        questionId2 = keccak256(abi.encodePacked("question2"));

        conditionalTokens.prepareCondition(ORACLE1, questionId1, 2);
        conditionalTokens.prepareCondition(ORACLE2, questionId2, 2);

        conditionId1 = conditionalTokens.getConditionId(ORACLE1, questionId1, 2);
        conditionId2 = conditionalTokens.getConditionId(ORACLE2, questionId2, 2);

        collateralToken.mint(TRADER, FUNDING);
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMakerFactory), FUNDING);

        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = conditionId1;
        conditionIds[1] = conditionId2;

        vm.prank(TRADER);
        lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens, IERC20(address(collateralToken)), conditionIds, 0, whitelist, FUNDING
        );

        bytes32 c1o1CollectionId = conditionalTokens.getCollectionId(NULL_BYTES32, conditionId1, 1);
        bytes32 c1o2CollectionId = conditionalTokens.getCollectionId(NULL_BYTES32, conditionId1, 2);

        positionId1 = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)), conditionalTokens.getCollectionId(c1o1CollectionId, conditionId2, 1)
        );
        positionId2 = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)), conditionalTokens.getCollectionId(c1o2CollectionId, conditionId2, 1)
        );
        positionId3 = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)), conditionalTokens.getCollectionId(c1o1CollectionId, conditionId2, 2)
        );
        positionId4 = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)), conditionalTokens.getCollectionId(c1o2CollectionId, conditionId2, 2)
        );
    }

    function testHappyPath() public {
        // should have conditions in the system with the listed IDs
        assertEq(conditionalTokens.payoutNumerators(conditionId1, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(conditionId2, 0), 0);

        // should have an LMSR deployed with the correct funding
        assertEq(lmsrMarketMaker.funding(), FUNDING);
        assertEq(lmsrMarketMaker.atomicOutcomeSlotCount(), 4);

        // LMSR should have the correct amount of tokens at the specified positions
        assertEq(conditionalTokens.balanceOf(address(lmsrMarketMaker), positionId1), FUNDING);
        assertEq(conditionalTokens.balanceOf(address(lmsrMarketMaker), positionId2), FUNDING);
        assertEq(conditionalTokens.balanceOf(address(lmsrMarketMaker), positionId3), FUNDING);
        assertEq(conditionalTokens.balanceOf(address(lmsrMarketMaker), positionId4), FUNDING);

        // users should be able to buy a position
        uint256 amount = 1e18;
        collateralToken.mint(TRADER, amount);
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMaker), amount);
        int256[] memory buyAmounts = new int256[](4);
        buyAmounts[0] = 1e9;
        buyAmounts[1] = 0;
        buyAmounts[2] = 1e9;
        buyAmounts[3] = 0;
        vm.prank(TRADER);
        lmsrMarketMaker.trade(buyAmounts, 0);

        // should have the correct amount of tokens at the specified positions
        assertEq(conditionalTokens.balanceOf(TRADER, positionId1), 1e9);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId2), 0);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId3), 1e9);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId4), 0);

        // users should be able to make complex buy/sell orders
        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);
        buyAmounts[0] = -1e9;
        buyAmounts[1] = 0;
        buyAmounts[2] = -1e9;
        buyAmounts[3] = 0;
        vm.prank(TRADER);
        lmsrMarketMaker.trade(buyAmounts, 1e18);

        // should have the correct amount of tokens at the specified positions
        assertEq(conditionalTokens.balanceOf(TRADER, positionId1), 0);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId2), 0);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId3), 0);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId4), 0);
    }
}
