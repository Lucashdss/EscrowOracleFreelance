//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
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
    address private client;
    address private freelancer;

    //constructor to initialize the contract
    constructor(address _freelancer, uint256 _deliveryPeriod) payable {
        client = msg.sender;
        freelancer = _freelancer;
        amountToRelease = msg.value;

        deadline = block.timestamp + _deliveryPeriod;

        state = EscrowState.FUNDED;
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

    function releaseFunds() external OnlyPerformUpkeep {
        if (state != EscrowState.DELIVERED) {
            revert Errors.InvalidState();
        }
        if (!deliveryConfirmed) {
            revert Errors.DeliverNotConfirmed();
        }

        state = EscrowState.RELEASED;

        (bool success, ) = payable(freelancer).call{value: amountToRelease}("");
        if (!success) {
            revert Errors.TransferFailed();
        }
    }

    function DeadlinePassedRefundClient() external view OnlyPerformUpkeep {
        (bool success, ) = payable(client).call{value: amountToRelease}("");
        require(success, "ETH transfer failed");
    }

    function getDeadline() external view returns (uint256) {
        return deadline;
    }

    function getAmountToRelease() external view returns (uint256) {
        return amountToRelease;
    }

    function getClientAdress() external view returns (address) {
        return client;
    }

    function getFreelancerAdress() external view returns (address) {
        return freelancer;
    }

    modifier OnlyClient() {
        require(msg.sender == client, "Not client");
        _;
    }

    modifier OnlyFreelancer() {
        require(msg.sender == freelancer, "Not freelancer");
        _;
    }

    modifier OnlyPerformUpkeep() {
        require(
            isPerformingUpkeep,
            "releaseFunds can only be called by performUpkeep"
        );
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
            performData = ""; // No additional data needed for performUpkeep
            return (upkeepNeeded, performData);
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        isPerformingUpkeep = true;
        releaseFunds();
        isPerformingUpkeep = false;
    }
}
