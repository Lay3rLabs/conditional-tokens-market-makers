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

abstract contract LMSRGasCostsTests is Test {
    ConditionalTokens public conditionalTokens;
    LMSRMarketMakerFactory public lmsrMarketMakerFactory;
    ERC20Mintable public collateralToken;
    Whitelist public whitelist;

    uint256 public constant TOTAL_COLLATERAL_AVAILABLE = 1e19;
    uint256 public constant FUNDING = 1e17;
    uint64 public constant FEE_FACTOR = 0;

    address public LMSR_OWNER = vm.addr(1);
    address public ORACLE = vm.addr(2);
    address public TRADER = vm.addr(3);

    // to be set by child tests
    uint256 internal numConditions = 0;
    uint256 internal outcomesPerCondition = 0;

    function setUp() public virtual {
        conditionalTokens = new ConditionalTokens("");
        lmsrMarketMakerFactory = new LMSRMarketMakerFactory();
        collateralToken = new ERC20Mintable();
        whitelist = new Whitelist(LMSR_OWNER);

        address[] memory users = new address[](1);
        users[0] = TRADER;
        vm.prank(LMSR_OWNER);
        whitelist.addToWhitelist(users);

        collateralToken.mint(LMSR_OWNER, TOTAL_COLLATERAL_AVAILABLE);
        collateralToken.mint(TRADER, TOTAL_COLLATERAL_AVAILABLE);

        vm.prank(LMSR_OWNER);
        collateralToken.approve(address(lmsrMarketMakerFactory), type(uint256).max);
    }

    function testHappyPath() public {
        // prepare conditions
        bytes32[] memory conditionIds = new bytes32[](numConditions);
        for (uint256 i = 0; i < numConditions; i++) {
            bytes32 questionId = keccak256(abi.encodePacked("question", i));
            conditionalTokens.prepareCondition(ORACLE, questionId, outcomesPerCondition);
            conditionIds[i] = conditionalTokens.getConditionId(ORACLE, questionId, outcomesPerCondition);
        }

        // create market maker
        vm.prank(LMSR_OWNER);
        LMSRMarketMaker lmsrMarketMaker = lmsrMarketMakerFactory.createLMSRMarketMaker(
            conditionalTokens, IERC20(address(collateralToken)), conditionIds, FEE_FACTOR, whitelist, FUNDING
        );

        // approve LMSR for trading
        vm.prank(TRADER);
        collateralToken.approve(address(lmsrMarketMaker), type(uint256).max);
        vm.prank(TRADER);
        conditionalTokens.setApprovalForAll(address(lmsrMarketMaker), true);

        // buy tokens
        int256[] memory buyAmounts = new int256[](outcomesPerCondition ** numConditions);
        for (uint256 i = 0; i < outcomesPerCondition ** numConditions; i++) {
            buyAmounts[i] = i % 2 != 0 ? int256(0) : int256(1e16);
        }

        vm.prank(TRADER);
        lmsrMarketMaker.trade(buyAmounts, 0);

        // sell tokens
        int256[] memory sellAmounts = new int256[](outcomesPerCondition ** numConditions);
        for (uint256 i = 0; i < outcomesPerCondition ** numConditions; i++) {
            sellAmounts[i] = i % 2 != 0 ? int256(0) : int256(-5e15);
        }

        vm.prank(TRADER);
        lmsrMarketMaker.trade(sellAmounts, 0);
    }
}

contract LMSRGasCostsTests_1_2 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 1;
        outcomesPerCondition = 2;
    }
}

contract LMSRGasCostsTests_1_3 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 1;
        outcomesPerCondition = 3;
    }
}

contract LMSRGasCostsTests_1_4 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 1;
        outcomesPerCondition = 4;
    }
}

contract LMSRGasCostsTests_1_10 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 1;
        outcomesPerCondition = 10;
    }
}

contract LMSRGasCostsTests_2_2 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 2;
        outcomesPerCondition = 2;
    }
}

contract LMSRGasCostsTests_2_3 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 2;
        outcomesPerCondition = 3;
    }
}

contract LMSRGasCostsTests_2_4 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 2;
        outcomesPerCondition = 4;
    }
}

contract LMSRGasCostsTests_3_2 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 3;
        outcomesPerCondition = 2;
    }
}

contract LMSRGasCostsTests_3_3 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 3;
        outcomesPerCondition = 3;
    }
}

contract LMSRGasCostsTests_4_2 is LMSRGasCostsTests {
    function setUp() public override {
        super.setUp();
        numConditions = 4;
        outcomesPerCondition = 2;
    }
}
