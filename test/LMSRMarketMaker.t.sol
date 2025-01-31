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

contract LMSRMarketMakerTests is Test {
    ConditionalTokens public conditionalTokens;
    LMSRMarketMakerFactory public lmsrMarketMakerFactory;
    ERC20Mintable public collateralToken;

    bytes32 public constant NULL_BYTES32 = bytes32(0);
    uint256 public constant TOKEN_COUNT = 1e18;
    uint256 public constant LOOP_COUNT = 10;
    uint256 public constant NUM_OUTCOMES = 2;

    address public ORACLE = vm.addr(1);
    address public TRADER = vm.addr(2);
    address public INVESTOR = vm.addr(3);
    bytes32 public questionId;
    bytes32 public conditionId;
    uint256 public positionId1;
    uint256 public positionId2;
    uint256[] public partition;
    bytes32[] public conditionIds;

    function setUp() public virtual {
        conditionalTokens = new ConditionalTokens("");
        lmsrMarketMakerFactory = new LMSRMarketMakerFactory();
        collateralToken = new ERC20Mintable();

        questionId = keccak256(abi.encodePacked("question"));
        conditionalTokens.prepareCondition(ORACLE, questionId, NUM_OUTCOMES);
        conditionId = conditionalTokens.getConditionId(ORACLE, questionId, NUM_OUTCOMES);

        positionId1 = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)), conditionalTokens.getCollectionId(NULL_BYTES32, conditionId, 1)
        );
        positionId2 = conditionalTokens.getPositionId(
            IERC20(address(collateralToken)), conditionalTokens.getCollectionId(NULL_BYTES32, conditionId, 2)
        );

        conditionIds = new bytes32[](1);
        conditionIds[0] = conditionId;

        partition = new uint256[](NUM_OUTCOMES);
        for (uint256 i = 0; i < NUM_OUTCOMES; i++) {
            partition[i] = 1 << i;
        }
    }

    function testCreateAndClose() public {
        uint256 funding = 100;

        collateralToken.mint(TRADER, funding);
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMakerFactory), funding);

        vm.prank(TRADER);
        LMSRMarketMaker lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens, IERC20(address(collateralToken)), conditionIds, 0, Whitelist(address(0)), funding
        );

        // close
        vm.prank(TRADER);
        lmsrMarketMaker.close();

        // cannot close again
        vm.expectRevert("This Market has already been closed");
        vm.prank(TRADER);
        lmsrMarketMaker.close();

        // sell all outcomes
        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);
        vm.prank(TRADER);
        conditionalTokens.mergePositions(
            IERC20(address(collateralToken)), NULL_BYTES32, conditionId, partition, funding
        );

        assertEq(collateralToken.balanceOf(TRADER), funding);
    }

    function testBuySell() public {
        uint256 funding = 1e18;
        uint256 tokenCount = 1e15;

        collateralToken.mint(INVESTOR, funding);
        vm.prank(INVESTOR);
        collateralToken.approve(address(lmsrMarketMakerFactory), funding);

        vm.prank(INVESTOR);
        LMSRMarketMaker lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens,
            IERC20(address(collateralToken)),
            conditionIds,
            5e16, // 5% fee
            Whitelist(address(0)),
            funding
        );

        // buy outcome tokens
        int256[] memory outcomeTokenAmounts = new int256[](NUM_OUTCOMES);
        outcomeTokenAmounts[0] = int256(tokenCount);
        int256 outcomeTokenCost = lmsrMarketMaker.calcNetCost(outcomeTokenAmounts);
        int256 fee = int256(lmsrMarketMaker.calcMarketFee(uint256(outcomeTokenCost)));
        // 5% fee
        assertEq(fee, (outcomeTokenCost * 5) / 100);

        int256 cost = fee + outcomeTokenCost;
        collateralToken.mint(TRADER, uint256(cost));
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMaker), uint256(cost));

        vm.prank(TRADER);
        int256 actualCost = lmsrMarketMaker.trade(outcomeTokenAmounts, cost);
        assertEq(actualCost, cost);

        assertEq(conditionalTokens.balanceOf(TRADER, positionId1), tokenCount);
        assertEq(collateralToken.balanceOf(TRADER), 0);

        // sell outcome tokens
        outcomeTokenAmounts[0] = -int256(tokenCount);
        int256 outcomeTokenProfit = -lmsrMarketMaker.calcNetCost(outcomeTokenAmounts);
        fee = int256(lmsrMarketMaker.calcMarketFee(uint256(outcomeTokenProfit)));
        int256 profit = outcomeTokenProfit - fee;

        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);
        vm.prank(TRADER);
        int256 actualProfit = -lmsrMarketMaker.trade(outcomeTokenAmounts, -profit);
        assertEq(actualProfit, profit);

        assertEq(conditionalTokens.balanceOf(TRADER, positionId1), 0);
        assertEq(collateralToken.balanceOf(TRADER), uint256(profit));
    }

    function testShortSell() public {
        uint256 funding = 1e18;
        uint256 tokenCount = 1e15;

        collateralToken.mint(INVESTOR, funding);
        vm.prank(INVESTOR);
        collateralToken.approve(address(lmsrMarketMakerFactory), funding);

        vm.prank(INVESTOR);
        LMSRMarketMaker lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens,
            IERC20(address(collateralToken)),
            conditionIds,
            5e4, // 5% fee
            Whitelist(address(0)),
            funding
        );

        // short sell outcome tokens
        int256[] memory outcomeTokenAmounts = new int256[](NUM_OUTCOMES);
        outcomeTokenAmounts[1] = int256(tokenCount);
        int256 outcomeTokenCost = lmsrMarketMaker.calcNetCost(outcomeTokenAmounts);
        int256 fee = int256(lmsrMarketMaker.calcMarketFee(uint256(outcomeTokenCost)));
        int256 cost = outcomeTokenCost + fee;

        collateralToken.mint(TRADER, uint256(cost));
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMaker), uint256(cost));

        vm.prank(TRADER);
        int256 actualCost = lmsrMarketMaker.trade(outcomeTokenAmounts, cost);
        assertEq(actualCost, cost);

        assertEq(collateralToken.balanceOf(TRADER), 0);
        assertEq(conditionalTokens.balanceOf(TRADER, positionId2), tokenCount);
    }

    function testTradeStress() public {
        uint256 funding = 1e16;

        collateralToken.mint(INVESTOR, funding);
        vm.prank(INVESTOR);
        collateralToken.approve(address(lmsrMarketMakerFactory), funding);

        vm.prank(INVESTOR);
        LMSRMarketMaker lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens, IERC20(address(collateralToken)), conditionIds, 0, Whitelist(address(0)), funding
        );

        // get ready for trading
        uint256 tradingStipend = 1e19;
        collateralToken.mint(TRADER, tradingStipend * 2);
        vm.prank(TRADER);
        collateralToken.approve(address(conditionalTokens), tradingStipend);
        vm.prank(TRADER);
        conditionalTokens.splitPosition(
            IERC20(address(collateralToken)), NULL_BYTES32, conditionId, partition, tradingStipend
        );

        // allow all trading
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMaker), type(uint256).max);
        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);

        for (uint256 i = 0; i < LOOP_COUNT; i++) {
            int256[] memory outcomeTokenAmounts = new int256[](NUM_OUTCOMES);
            outcomeTokenAmounts[0] = -4e15;
            outcomeTokenAmounts[1] = 2e14;
            int256 netCost = lmsrMarketMaker.calcNetCost(outcomeTokenAmounts);

            vm.prank(TRADER);
            int256 actualCost = lmsrMarketMaker.trade(outcomeTokenAmounts, netCost);
            assertEq(actualCost, netCost);
        }
    }
}
