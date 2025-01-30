// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ConditionalTokens} from "@lay3rlabs/conditional-tokens-contracts/ConditionalTokens.sol";
import {CTHelpers} from "@lay3rlabs/conditional-tokens-contracts/CTHelpers.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

library CeilDiv {
    // calculates ceil(x/y)
    function ceildiv(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > 0) return ((x - 1) / y) + 1;
        return x / y;
    }
}

contract FixedProductMarketMaker is Initializable, ERC20, IERC1155Receiver {
    using CeilDiv for uint256;

    uint256 constant ONE = 10 ** 18;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    uint256 internal _totalSupply;

    ConditionalTokens public conditionalTokens;
    IERC20 public collateralToken;
    bytes32[] public conditionIds;
    uint256 public fee;
    uint256 internal feePoolWeight;

    uint256[] outcomeSlotCounts;
    bytes32[][] collectionIds;
    uint256[] positionIds;
    mapping(address => uint256) withdrawnFees;
    uint256 internal totalWithdrawnFees;

    event FPMMFundingAdded(address indexed funder, uint256[] amountsAdded, uint256 sharesMinted);
    event FPMMFundingRemoved(
        address indexed funder, uint256[] amountsRemoved, uint256 collateralRemovedFromFeePool, uint256 sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint256 investmentAmount,
        uint256 feeAmount,
        uint256 indexed outcomeIndex,
        uint256 outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint256 returnAmount,
        uint256 feeAmount,
        uint256 indexed outcomeIndex,
        uint256 outcomeTokensSold
    );

    constructor() ERC20("Fixed Product Market Maker", "FPMM") {}

    function initialize(
        ConditionalTokens _conditionalTokens,
        IERC20 _collateralToken,
        bytes32[] memory _conditionIds,
        uint256 _fee
    ) public initializer {
        conditionalTokens = _conditionalTokens;
        collateralToken = _collateralToken;
        conditionIds = _conditionIds;
        fee = _fee;

        uint256 atomicOutcomeSlotCount = 1;
        outcomeSlotCounts = new uint256[](conditionIds.length);
        for (uint256 i = 0; i < conditionIds.length; i++) {
            uint256 outcomeSlotCount = conditionalTokens.getOutcomeSlotCount(conditionIds[i]);
            atomicOutcomeSlotCount *= outcomeSlotCount;
            outcomeSlotCounts[i] = outcomeSlotCount;
        }
        require(atomicOutcomeSlotCount > 1, "conditions must be valid");

        collectionIds = new bytes32[][](conditionIds.length);
        _recordCollectionIDsForAllConditions(conditionIds.length, bytes32(0));
        require(positionIds.length == atomicOutcomeSlotCount, "position IDs construction failed!?");
    }

    function _recordCollectionIDsForAllConditions(uint256 conditionsLeft, bytes32 parentCollectionId) private {
        if (conditionsLeft == 0) {
            positionIds.push(CTHelpers.getPositionId(collateralToken, parentCollectionId));
            return;
        }

        conditionsLeft--;

        uint256 outcomeSlotCount = outcomeSlotCounts[conditionsLeft];

        collectionIds[conditionsLeft].push(parentCollectionId);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            _recordCollectionIDsForAllConditions(
                conditionsLeft, CTHelpers.getCollectionId(parentCollectionId, conditionIds[conditionsLeft], 1 << i)
            );
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function getPoolBalances() private view returns (uint256[] memory) {
        address[] memory thises = new address[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            thises[i] = address(this);
        }
        return conditionalTokens.balanceOfBatch(thises, positionIds);
    }

    function generateBasicPartition(uint256 outcomeSlotCount) private pure returns (uint256[] memory partition) {
        partition = new uint256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
    }

    function splitPositionThroughAllConditions(uint256 amount) private {
        for (uint256 i = conditionIds.length - 1; int256(i) >= 0; i--) {
            uint256[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for (uint256 j = 0; j < collectionIds[i].length; j++) {
                conditionalTokens.splitPosition(
                    collateralToken, collectionIds[i][j], conditionIds[i], partition, amount
                );
            }
        }
    }

    function mergePositionsThroughAllConditions(uint256 amount) private {
        for (uint256 i = 0; i < conditionIds.length; i++) {
            uint256[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for (uint256 j = 0; j < collectionIds[i].length; j++) {
                conditionalTokens.mergePositions(
                    collateralToken, collectionIds[i][j], conditionIds[i], partition, amount
                );
            }
        }
    }

    function collectedFees() external view returns (uint256) {
        return feePoolWeight - totalWithdrawnFees;
    }

    function feesWithdrawableBy(address account) public view returns (uint256) {
        uint256 rawAmount = (feePoolWeight * balanceOf(account)) / totalSupply();
        return rawAmount - withdrawnFees[account];
    }

    function withdrawFees(address account) public {
        uint256 rawAmount = (feePoolWeight * balanceOf(account)) / totalSupply();
        uint256 withdrawableAmount = rawAmount - withdrawnFees[account];
        if (withdrawableAmount > 0) {
            withdrawnFees[account] = rawAmount;
            totalWithdrawnFees += withdrawableAmount;
            require(collateralToken.transfer(account, withdrawableAmount), "withdrawal transfer failed");
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal {
        if (from != address(0)) {
            withdrawFees(from);
        }

        uint256 totalSupply = totalSupply();
        uint256 withdrawnFeesTransfer = totalSupply == 0 ? amount : (feePoolWeight * amount) / totalSupply;

        if (from != address(0)) {
            withdrawnFees[from] -= withdrawnFeesTransfer;
            totalWithdrawnFees -= withdrawnFeesTransfer;
        } else {
            feePoolWeight += withdrawnFeesTransfer;
        }
        if (to != address(0)) {
            withdrawnFees[to] += withdrawnFeesTransfer;
            totalWithdrawnFees += withdrawnFeesTransfer;
        } else {
            feePoolWeight -= withdrawnFeesTransfer;
        }
    }

    function addFunding(uint256 addedFunds, uint256[] calldata distributionHint) external {
        require(addedFunds > 0, "funding must be non-zero");

        uint256[] memory sendBackAmounts = new uint256[](positionIds.length);
        uint256 poolShareSupply = totalSupply();
        uint256 mintAmount;
        if (poolShareSupply > 0) {
            require(distributionHint.length == 0, "cannot use distribution hint after initial funding");
            uint256[] memory poolBalances = getPoolBalances();
            uint256 poolWeight = 0;
            for (uint256 i = 0; i < poolBalances.length; i++) {
                uint256 balance = poolBalances[i];
                if (poolWeight < balance) poolWeight = balance;
            }

            for (uint256 i = 0; i < poolBalances.length; i++) {
                uint256 remaining = (addedFunds * poolBalances[i]) / poolWeight;
                sendBackAmounts[i] = addedFunds - remaining;
            }

            mintAmount = (addedFunds * poolShareSupply) / poolWeight;
        } else {
            if (distributionHint.length > 0) {
                require(distributionHint.length == positionIds.length, "hint length off");
                uint256 maxHint = 0;
                for (uint256 i = 0; i < distributionHint.length; i++) {
                    uint256 hint = distributionHint[i];
                    if (maxHint < hint) maxHint = hint;
                }

                for (uint256 i = 0; i < distributionHint.length; i++) {
                    uint256 remaining = (addedFunds * distributionHint[i]) / maxHint;
                    require(remaining > 0, "must hint a valid distribution");
                    sendBackAmounts[i] = addedFunds - remaining;
                }
            }

            mintAmount = addedFunds;
        }

        require(collateralToken.transferFrom(msg.sender, address(this), addedFunds), "funding transfer failed");
        require(collateralToken.approve(address(conditionalTokens), addedFunds), "approval for splits failed");
        splitPositionThroughAllConditions(addedFunds);

        _mint(msg.sender, mintAmount);

        conditionalTokens.safeBatchTransferFrom(address(this), msg.sender, positionIds, sendBackAmounts, "");

        // transform sendBackAmounts to array of amounts added
        for (uint256 i = 0; i < sendBackAmounts.length; i++) {
            sendBackAmounts[i] = addedFunds - sendBackAmounts[i];
        }

        emit FPMMFundingAdded(msg.sender, sendBackAmounts, mintAmount);
    }

    function removeFunding(uint256 sharesToBurn) external {
        uint256[] memory poolBalances = getPoolBalances();

        uint256[] memory sendAmounts = new uint256[](poolBalances.length);

        uint256 poolShareSupply = totalSupply();
        for (uint256 i = 0; i < poolBalances.length; i++) {
            sendAmounts[i] = (poolBalances[i] * sharesToBurn) / poolShareSupply;
        }

        uint256 collateralRemovedFromFeePool = collateralToken.balanceOf(address(this));

        _burn(msg.sender, sharesToBurn);
        collateralRemovedFromFeePool = collateralRemovedFromFeePool - collateralToken.balanceOf(address(this));

        conditionalTokens.safeBatchTransferFrom(address(this), msg.sender, positionIds, sendAmounts, "");

        emit FPMMFundingRemoved(msg.sender, sendAmounts, collateralRemovedFromFeePool, sharesToBurn);
    }

    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata)
        public
        view
        returns (bytes4)
    {
        if (operator == address(this)) {
            return this.onERC1155Received.selector;
        }
        return 0x0;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) public view returns (bytes4) {
        if (operator == address(this) && from == address(0)) {
            return this.onERC1155BatchReceived.selector;
        }
        return 0x0;
    }

    function calcBuyAmount(uint256 investmentAmount, uint256 outcomeIndex) public view returns (uint256) {
        require(outcomeIndex < positionIds.length, "invalid outcome index");

        uint256[] memory poolBalances = getPoolBalances();
        uint256 investmentAmountMinusFees = investmentAmount - ((investmentAmount * fee) / ONE);
        uint256 buyTokenPoolBalance = poolBalances[outcomeIndex];
        uint256 endingOutcomeBalance = buyTokenPoolBalance * ONE;
        for (uint256 i = 0; i < poolBalances.length; i++) {
            if (i != outcomeIndex) {
                uint256 poolBalance = poolBalances[i];
                endingOutcomeBalance =
                    (endingOutcomeBalance * poolBalance).ceildiv(poolBalance + investmentAmountMinusFees);
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return buyTokenPoolBalance + investmentAmountMinusFees - endingOutcomeBalance.ceildiv(ONE);
    }

    function calcSellAmount(uint256 returnAmount, uint256 outcomeIndex)
        public
        view
        returns (uint256 outcomeTokenSellAmount)
    {
        require(outcomeIndex < positionIds.length, "invalid outcome index");

        uint256[] memory poolBalances = getPoolBalances();
        uint256 returnAmountPlusFees = (returnAmount * ONE) / (ONE - fee);
        uint256 sellTokenPoolBalance = poolBalances[outcomeIndex];
        uint256 endingOutcomeBalance = sellTokenPoolBalance * ONE;
        for (uint256 i = 0; i < poolBalances.length; i++) {
            if (i != outcomeIndex) {
                uint256 poolBalance = poolBalances[i];
                endingOutcomeBalance = (endingOutcomeBalance * poolBalance).ceildiv(poolBalance - returnAmountPlusFees);
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return returnAmountPlusFees + endingOutcomeBalance.ceildiv(ONE) - sellTokenPoolBalance;
    }

    function buy(uint256 investmentAmount, uint256 outcomeIndex, uint256 minOutcomeTokensToBuy) external {
        uint256 outcomeTokensToBuy = calcBuyAmount(investmentAmount, outcomeIndex);
        require(outcomeTokensToBuy >= minOutcomeTokensToBuy, "minimum buy amount not reached");

        require(collateralToken.transferFrom(msg.sender, address(this), investmentAmount), "cost transfer failed");

        uint256 feeAmount = (investmentAmount * fee) / ONE;
        feePoolWeight += feeAmount;
        uint256 investmentAmountMinusFees = investmentAmount - feeAmount;
        require(
            collateralToken.approve(address(conditionalTokens), investmentAmountMinusFees), "approval for splits failed"
        );
        splitPositionThroughAllConditions(investmentAmountMinusFees);

        conditionalTokens.safeTransferFrom(address(this), msg.sender, positionIds[outcomeIndex], outcomeTokensToBuy, "");

        emit FPMMBuy(msg.sender, investmentAmount, feeAmount, outcomeIndex, outcomeTokensToBuy);
    }

    function sell(uint256 returnAmount, uint256 outcomeIndex, uint256 maxOutcomeTokensToSell) external {
        uint256 outcomeTokensToSell = calcSellAmount(returnAmount, outcomeIndex);
        require(outcomeTokensToSell <= maxOutcomeTokensToSell, "maximum sell amount exceeded");

        conditionalTokens.safeTransferFrom(
            msg.sender, address(this), positionIds[outcomeIndex], outcomeTokensToSell, ""
        );

        uint256 feeAmount = (returnAmount * fee) / (ONE - fee);
        feePoolWeight += feeAmount;
        uint256 returnAmountPlusFees = returnAmount + feeAmount;
        mergePositionsThroughAllConditions(returnAmountPlusFees);

        require(collateralToken.transfer(msg.sender, returnAmount), "return transfer failed");

        emit FPMMSell(msg.sender, returnAmount, feeAmount, outcomeIndex, outcomeTokensToSell);
    }
}
