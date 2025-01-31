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

contract LMSRMarketMakerBuySellTests is Test {
    ConditionalTokens public conditionalTokens;
    LMSRMarketMakerFactory public lmsrMarketMakerFactory;
    LMSRMarketMaker public lmsrMarketMaker;
    ERC20Mintable public collateralToken;

    bytes32 public constant NULL_BYTES32 = bytes32(0);
    uint256 public constant TOKEN_COUNT = 1e18;
    uint256 public constant LOOP_COUNT = 10;

    address public ORACLE = vm.addr(1);
    address public TRADER = vm.addr(2);
    bytes32 public questionId;
    bytes32 public conditionId;
    uint256[] public partition;

    function setUp() public virtual {
        conditionalTokens = new ConditionalTokens("");
        lmsrMarketMakerFactory = new LMSRMarketMakerFactory();
        collateralToken = new ERC20Mintable();
    }

    function manualSetUp(
        uint256 creatorPrivateKey,
        uint256 numOutcomes,
        uint256 funding
    ) public virtual {
        questionId = keccak256(abi.encodePacked("question", creatorPrivateKey));
        conditionalTokens.prepareCondition(ORACLE, questionId, numOutcomes);
        conditionId = conditionalTokens.getConditionId(
            ORACLE,
            questionId,
            numOutcomes
        );

        partition = new uint256[](numOutcomes);
        for (uint256 i = 0; i < numOutcomes; i++) {
            partition[i] = 1 << i;
        }

        address creator = vm.addr(creatorPrivateKey);

        collateralToken.mint(creator, funding);
        vm.prank(creator);
        collateralToken.approve(address(lmsrMarketMakerFactory), funding);

        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = conditionId;

        vm.prank(creator);
        lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens,
            IERC20(address(collateralToken)),
            conditionIds,
            0,
            Whitelist(address(0)),
            funding
        );
    }

    function testMovePriceToZeroAfterLotsOfOutcomeSold() public {
        manualSetUp(3, 2, 1e17);

        collateralToken.mint(TRADER, TOKEN_COUNT * LOOP_COUNT);
        vm.prank(TRADER);
        collateralToken.approve(
            address(conditionalTokens),
            TOKEN_COUNT * LOOP_COUNT
        );

        vm.prank(TRADER);
        conditionalTokens.splitPosition(
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            TOKEN_COUNT * LOOP_COUNT
        );
        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);

        // user sells tokens
        uint256 initialBalance = collateralToken.balanceOf(TRADER);
        int256[] memory outcomeTokenAmounts = new int256[](2);
        outcomeTokenAmounts[0] = 0;
        outcomeTokenAmounts[1] = -int256(TOKEN_COUNT);
        int256 profit;
        for (uint256 i = 0; i < LOOP_COUNT; i++) {
            profit = -lmsrMarketMaker.calcNetCost(outcomeTokenAmounts);
            if (profit == 0) {
                break;
            }

            // selling tokens
            vm.prank(TRADER);
            int256 actualProfit = lmsrMarketMaker.trade(
                outcomeTokenAmounts,
                -int256(profit)
            );
            assertEq(-actualProfit, profit);
        }
        // selling of tokens is worth less than 1 Wei
        assertEq(profit, 0);
        // user's balance increased
        assertGt(collateralToken.balanceOf(TRADER), initialBalance);
    }

    function movePriceToOneAfterLotsOfOutcomeBought(
        uint256 investorPrivateKey,
        uint256 funding,
        uint256 tokenCount
    ) public {
        manualSetUp(investorPrivateKey, 2, funding);

        // user buys collateral
        collateralToken.mint(TRADER, tokenCount * LOOP_COUNT);

        // user buys outcome tokens from market maker
        int256[] memory outcomeTokenAmounts = new int256[](2);
        outcomeTokenAmounts[0] = 0;
        outcomeTokenAmounts[1] = int256(tokenCount);
        uint256 cost;
        for (uint256 i = 0; i < LOOP_COUNT; i++) {
            cost = uint256(lmsrMarketMaker.calcNetCost(outcomeTokenAmounts));

            // buying tokens
            vm.prank(TRADER);
            collateralToken.approve(address(lmsrMarketMaker), cost);
            vm.prank(TRADER);
            int256 actualCost = lmsrMarketMaker.trade(
                outcomeTokenAmounts,
                int256(cost)
            );
            assertEq(uint256(actualCost), cost);
        }

        // price is at least 1
        assert(cost >= tokenCount);
    }

    function testMovePriceToOneAfterLotsOfOutcomeBought() public {
        movePriceToOneAfterLotsOfOutcomeBought(100, 1e17, 1e18);
        movePriceToOneAfterLotsOfOutcomeBought(101, 1, 10);
        movePriceToOneAfterLotsOfOutcomeBought(102, 1, 1e18);
    }

    function testAllowBuyingAndSellingOutcomeTokensInSameTransaction() public {
        manualSetUp(3, 4, 1e18);

        uint256 initialOutcomeTokenCount = 1e18;
        uint256 initialCollateralTokenCount = 10e18;

        // user buys all outcomes
        collateralToken.mint(
            TRADER,
            initialOutcomeTokenCount + initialCollateralTokenCount
        );
        vm.prank(TRADER);
        collateralToken.approve(
            address(conditionalTokens),
            initialOutcomeTokenCount
        );

        vm.prank(TRADER);
        conditionalTokens.splitPosition(
            IERC20(address(collateralToken)),
            NULL_BYTES32,
            conditionId,
            partition,
            initialOutcomeTokenCount
        );

        // user trades with the market maker
        int256[] memory tradeValues = new int256[](4);
        tradeValues[0] = 5e17;
        tradeValues[1] = -1e18;
        tradeValues[2] = -1e17;
        tradeValues[3] = 2e18;

        int256 cost = lmsrMarketMaker.calcNetCost(tradeValues);
        if (cost > 0) {
            vm.prank(TRADER);
            collateralToken.approve(address(lmsrMarketMaker), uint256(cost));
        }

        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);

        vm.prank(TRADER);
        int256 actualCost = lmsrMarketMaker.trade(tradeValues, cost);
        assertEq(actualCost, cost);

        // all state transitions associated with trade have been performed
        for (uint256 i = 0; i < tradeValues.length; i++) {
            uint256 outcomeTokenAmount = conditionalTokens.balanceOf(
                TRADER,
                conditionalTokens.getPositionId(
                    IERC20(address(collateralToken)),
                    conditionalTokens.getCollectionId(
                        NULL_BYTES32,
                        conditionId,
                        1 << i
                    )
                )
            );
            assertEq(
                outcomeTokenAmount,
                uint256(int256(initialOutcomeTokenCount) + tradeValues[i])
            );
        }

        assertEq(
            collateralToken.balanceOf(TRADER),
            initialCollateralTokenCount - uint256(cost)
        );
    }
}
