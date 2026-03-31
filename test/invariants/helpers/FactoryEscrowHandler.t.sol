// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../../src/EscrowFreelance.sol";
import {EscrowFreelanceFactory} from "../../../src/EscrowFreelanceFactory.sol";

contract FactoryEscrowHandler is Test {
    EscrowFreelanceFactory internal immutable iFactory;
    EscrowFreelance[] internal iEscrows;
    address[] internal iClients;
    address[] internal iFreelancers;
    address[] internal iAdmins;

    constructor(
        EscrowFreelanceFactory factory,
        EscrowFreelance[] memory escrows,
        address[] memory clients,
        address[] memory freelancers,
        address[] memory admins
    ) {
        iFactory = factory;
        iEscrows = escrows;
        iClients = clients;
        iFreelancers = freelancers;
        iAdmins = admins;
    }

    function fund(uint256 escrowSeed, uint96 amount) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address client = iClients[escrowSeed % iClients.length];
        amount = uint96(bound(amount, 1, 25 ether));

        vm.deal(client, client.balance + amount);
        vm.prank(client);
        try escrow.fund{value: amount}(amount) {} catch {}
    }

    function markWorkSubmitted(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address freelancer = iFreelancers[escrowSeed % iFreelancers.length];

        vm.prank(freelancer);
        try escrow.markWorkSubmitted() {} catch {}
    }

    function confirmDelivery(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address client = iClients[escrowSeed % iClients.length];

        vm.prank(client);
        try escrow.confirmDelivery() {} catch {}
    }

    function requestModification(uint256 escrowSeed, uint32 extension) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address client = iClients[escrowSeed % iClients.length];
        extension = uint32(bound(extension, 1, 30 days));

        vm.prank(client);
        try escrow.requestModificationAndUpdateDeadline(extension) {} catch {}
    }

    function initiateDisputeAsClient(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address client = iClients[escrowSeed % iClients.length];

        vm.prank(client);
        try escrow.initiateDispute() {} catch {}
    }

    function initiateDisputeAsFreelancer(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address freelancer = iFreelancers[escrowSeed % iFreelancers.length];

        vm.prank(freelancer);
        try escrow.initiateDispute() {} catch {}
    }

    function resolveConflictToClient(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address client = iClients[escrowSeed % iClients.length];
        address admin = iAdmins[escrowSeed % iAdmins.length];

        vm.prank(admin);
        try escrow.resolveConflict(client) {} catch {}
    }

    function resolveConflictToFreelancer(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address freelancer = iFreelancers[escrowSeed % iFreelancers.length];
        address admin = iAdmins[escrowSeed % iAdmins.length];

        vm.prank(admin);
        try escrow.resolveConflict(freelancer) {} catch {}
    }

    function cancelEscrow(uint256 escrowSeed) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        address client = iClients[escrowSeed % iClients.length];

        vm.prank(client);
        try escrow.cancelEscrow() {} catch {}
    }

    function warpAfterDeadline(uint256 escrowSeed, uint32 extraTime) external {
        EscrowFreelance escrow = _escrowAt(escrowSeed);
        extraTime = uint32(bound(extraTime, 1, 30 days));
        vm.warp(escrow.getDeadline() + extraTime);
    }

    function processExpiredEscrows() external {
        try iFactory.processExpiredEscrows() {} catch {}
    }

    function escrowCount() external view returns (uint256) {
        return iEscrows.length;
    }

    function escrowAt(uint256 index) external view returns (EscrowFreelance) {
        return iEscrows[index];
    }

    function _escrowAt(uint256 seed) internal view returns (EscrowFreelance) {
        return iEscrows[seed % iEscrows.length];
    }
}
