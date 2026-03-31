// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../../src/EscrowFreelanceFactory.sol";

contract EscrowFreelanceHandler is Test {
    EscrowFreelance internal immutable iEscrow;
    EscrowFreelanceFactory internal immutable iFactory;
    address internal immutable iClient;
    address internal immutable iFreelancer;
    address internal immutable iAdmin;

    constructor(EscrowFreelance escrow, EscrowFreelanceFactory factory, address client, address freelancer, address admin) {
        iEscrow = escrow;
        iFactory = factory;
        iClient = client;
        iFreelancer = freelancer;
        iAdmin = admin;
    }

    function fund(uint96 amount) external {
        amount = uint96(bound(amount, 1, 25 ether));

        vm.deal(iClient, iClient.balance + amount);
        vm.prank(iClient);
        try iEscrow.fund{value: amount}(amount) {} catch {}
    }

    function markWorkSubmitted() external {
        vm.prank(iFreelancer);
        try iEscrow.markWorkSubmitted() {} catch {}
    }

    function confirmDelivery() external {
        vm.prank(iClient);
        try iEscrow.confirmDelivery() {} catch {}
    }

    function requestModification(uint32 extension) external {
        extension = uint32(bound(extension, 1, 30 days));

        vm.prank(iClient);
        try iEscrow.requestModificationAndUpdateDeadline(extension) {} catch {}
    }

    function initiateDisputeAsClient() external {
        vm.prank(iClient);
        try iEscrow.initiateDispute() {} catch {}
    }

    function initiateDisputeAsFreelancer() external {
        vm.prank(iFreelancer);
        try iEscrow.initiateDispute() {} catch {}
    }

    function resolveConflictToClient() external {
        vm.prank(iAdmin);
        try iEscrow.resolveConflict(iClient) {} catch {}
    }

    function resolveConflictToFreelancer() external {
        vm.prank(iAdmin);
        try iEscrow.resolveConflict(iFreelancer) {} catch {}
    }

    function cancelEscrow() external {
        vm.prank(iClient);
        try iEscrow.cancelEscrow() {} catch {}
    }

    function warpAfterDeadline(uint32 extraTime) external {
        extraTime = uint32(bound(extraTime, 1, 30 days));
        vm.warp(iEscrow.getDeadline() + extraTime);
    }

    function processExpiredEscrows() external {
        try iFactory.processExpiredEscrows() {} catch {}
    }
}
