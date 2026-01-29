//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Errors} from "./libraries/Errors.sol";

contract EscrowFreelance is AutomationCompatibleInterface {
    using Errors for *;

    enum EscrowState {
        CREATED,
        FUNDED,
        DELIVERED,
        RELEASED,
        REFUNDED
    }

    // variables are stored here
    EscrowState private state;
    bool private deliveryConfirmed;
    bool private isPerformingUpkeep;
    uint256 private deadline;
    uint256 private amountToRelease;
    uint256 private minimumPriceUSDinEther;
    address private immutable iClient;
    address private immutable iFreelancer;
    address internal immutable iDataFeed;

    //constructor to initialize the contract
    constructor(
        address _freelancer,
        uint256 _deliveryPeriod,
        address _dataFeed
    ) payable {
        iClient = msg.sender;
        iFreelancer = _freelancer;
        iDataFeed = _dataFeed;
        amountToRelease = msg.value;

        deadline = block.timestamp + _deliveryPeriod;

        if (msg.value == 0) {
            state = EscrowState.CREATED;
        } else {
            state = EscrowState.FUNDED;
        }
    }

    function markDelivered() external OnlyFreelancer {
        if (state != EscrowState.FUNDED) {
            revert Errors.InvalidState();
        }

        state = EscrowState.DELIVERED;
    }

    function confirmDelivery() external OnlyClient {
        if (state != EscrowState.DELIVERED) {
            revert Errors.InvalidState();
        }

        deliveryConfirmed = true;
    }

    function releaseFunds() internal OnlyPerformUpkeep {
        if (state != EscrowState.DELIVERED) {
            revert Errors.InvalidState();
        }
        if (!deliveryConfirmed) {
            revert Errors.DeliverNotConfirmed();
        }

        state = EscrowState.RELEASED;

        (bool success, ) = payable(iFreelancer).call{value: amountToRelease}(
            ""
        );
        if (!success) {
            revert Errors.TransferFailed();
        }
    }

    function fundEther() external payable OnlyClient {
        if (state == EscrowState.RELEASED || state == EscrowState.REFUNDED) {
            revert Errors.ContractHasBeenAlreadyReleasedOrRefunded();
        }

        amountToRelease += msg.value;

        if (amountToRelease < minimumPriceUSDinEther) {
            revert Errors.AmountIsInferiorToMinimumUSD();
        }
    }

    function convertAmountFromUSDtoETH(
        uint256 usdAmount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(iDataFeed);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Adjust to 18 decimals
        uint256 ethAmount = (usdAmount * 1e18) / adjustedPrice;
        return ethAmount;
    }

    function setMininumPriceUSD(uint256 usdAmount) external OnlyFreelancer {
        uint256 ethAmount = convertAmountFromUSDtoETH(usdAmount);
        if (state != EscrowState.CREATED) {
            revert Errors.ContractHasBeenAlreadyFunded();
        }

        minimumPriceUSDinEther = ethAmount;
    }

    function deadlinePassedRefundClient() internal OnlyPerformUpkeep {
        (bool success, ) = payable(iClient).call{value: amountToRelease}("");
        if (!success) revert Errors.InsufficientFunds();
    }

    function getDeadline() external view returns (uint256) {
        return deadline;
    }

    function getAmountToRelease() external view returns (uint256) {
        return amountToRelease;
    }

    function getClientAdress() external view returns (address) {
        return iClient;
    }

    function getFreelancerAdress() external view returns (address) {
        return iFreelancer;
    }

    function getScrowState() external view returns (EscrowState) {
        return state;
    }

    function getDeliveryConfirmedState() external view returns (bool) {
        return deliveryConfirmed;
    }

    function getVersion() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(iDataFeed);
        return priceFeed.version();
    }

    function getDataFeedAddress() external view returns (address) {
        return iDataFeed;
    }

    function getMinunumPriceUSD() external view returns (uint256) {
        return minimumPriceUSDinEther;
    }

    modifier OnlyClient() {
        if (msg.sender != iClient) {
            revert Errors.OnlyClient();
        }
        _;
    }

    modifier OnlyFreelancer() {
        if (msg.sender != iFreelancer) {
            revert Errors.OnlyFreelancer();
        }
        _;
    }

    modifier OnlyPerformUpkeep() {
        if (!isPerformingUpkeep) {
            revert Errors.NotPerformUpkeep();
        }
        _;
    }

    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // if deadline has passed and state is FUNDED, we need to perform upkeep to refund
        if (block.timestamp > deadline && state == EscrowState.FUNDED) {
            upkeepNeeded = true;
            performData = abi.encode(uint8(1)); // No additional data needed for performUpkeep
            return (upkeepNeeded, performData);
        } else if (state == EscrowState.DELIVERED && deliveryConfirmed) {
            upkeepNeeded = true;
            performData = abi.encode(uint8(2)); // No additional data needed for performUpkeep
            return (upkeepNeeded, performData);
        } else {
            upkeepNeeded = false;
            performData = "";
            return (upkeepNeeded, performData);
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        uint8 action = abi.decode(performData, (uint8));
        if (action == 1) {
            isPerformingUpkeep = true;
            deadlinePassedRefundClient();
            isPerformingUpkeep = false;
        } else if (action == 2) {
            isPerformingUpkeep = true;
            releaseFunds();
            isPerformingUpkeep = false;
        }
    }
}
