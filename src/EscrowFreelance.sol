//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract EscrowFreelance is AutomationCompatibleInterface {
    enum EscrowState {
        CREATED,
        FUNDED,
        DELIVERED,
        RELEASED,
        REFUNDED
    }

    // variables are stored here
    EscrowState public state;
    bool public deliveryConfirmed;
    bool public released;
    uint256 public deadline;
    uint256 public amountToRelease;
    address public client;
    address public freelancer;

    //constructor to initialize the contract
    constructor(address _freelancer, uint256 _deliveryPeriod) payable {
        client = msg.sender;
        freelancer = _freelancer;
        amountToRelease = msg.value;

        deadline = block.timestamp + _deliveryPeriod;

        state = EscrowState.FUNDED;
    }

    function markDelivered() external {
        require(msg.sender == freelancer, "Not freelancer");
        require(state == EscrowState.FUNDED, "Invalid state");

        state = EscrowState.DELIVERED;
    }

    function confirmDelivery() external {
        require(msg.sender == client, "Not client");
        require(state == EscrowState.DELIVERED, "Not delivered");

        deliveryConfirmed = true;
    }

    function checkUpkeep(
        bytes calldata
    ) external view returns (bool upkeepNeeded, bytes memory performData) {}

    function performUpkeep(bytes calldata performData) external {}
}
