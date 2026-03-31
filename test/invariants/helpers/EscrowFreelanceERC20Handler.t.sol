// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../../src/EscrowFreelanceFactory.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract EscrowFreelanceERC20Handler is Test {
    EscrowFreelance internal immutable iEscrow;
    EscrowFreelanceFactory internal immutable iFactory;
    MockERC20 internal immutable iToken;
    address internal immutable iClient;
    address internal immutable iFreelancer;
    address internal immutable iAdmin;

    constructor(
        EscrowFreelance escrow,
        EscrowFreelanceFactory factory,
        MockERC20 token,
        address client,
        address freelancer,
        address admin
    ) {
        iEscrow = escrow;
        iFactory = factory;
        iToken = token;
        iClient = client;
        iFreelancer = freelancer;
        iAdmin = admin;
    }

    function fund(uint96 amount) external {
        amount = uint96(bound(amount, 1, 500_000e18));

        iToken.mint(iClient, amount);
        vm.startPrank(iClient);
        iToken.approve(address(iEscrow), amount);
        try iEscrow.fund(amount) {} catch {}
        vm.stopPrank();
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
