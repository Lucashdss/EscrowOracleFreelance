// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EscrowFreelance} from "../../src/EscrowFreelance.sol";
import {DeployEscrow} from "../../script/DeployEscrow.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract EscrowFreelanceWithBPS is Test {
    EscrowFreelance escrowWithBPS;
    uint256 constant SEND_VALUE = 1 ether;
    uint256 constant BPS = 1000; // 10%

    function setUp() public {
        escrowWithBPS = new DeployEscrow().runWithETHandBPS();
    }

    function testFundingSendsUpfrontAndStoresRemainingBalance() public {
        address client = escrowWithBPS.getClientAddress();
        address freelancer = escrowWithBPS.getFreelancerAddress();

        vm.deal(client, 5 ether);

        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.prank(client);
        escrowWithBPS.fund{value: SEND_VALUE}(SEND_VALUE);

        uint256 expectedUpfront = (SEND_VALUE * BPS) / 10_000;
        uint256 expectedEscrowRemainder = SEND_VALUE - expectedUpfront;

        assertEq(
            freelancer.balance - freelancerBalanceBefore,
            expectedUpfront,
            "Freelancer should receive the configured upfront amount"
        );
        assertEq(
            escrowWithBPS.getAmountToRelease(),
            expectedEscrowRemainder,
            "Escrow should retain only the remaining amount"
        );
        assertEq(
            address(escrowWithBPS).balance,
            expectedEscrowRemainder,
            "Contract ETH balance should match releasable amount"
        );
    }

    function testFundingWith20PercentBpsSendsExpectedUpfront() public {
        EscrowFreelance escrow20Bps = _deployEscrowWithBps(2000); // 20%
        address client = escrow20Bps.getClientAddress();
        address freelancer = escrow20Bps.getFreelancerAddress();

        vm.deal(client, 5 ether);
        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.prank(client);
        escrow20Bps.fund{value: SEND_VALUE}(SEND_VALUE);

        uint256 expectedUpfront = (SEND_VALUE * 2000) / 10_000;
        assertEq(freelancer.balance - freelancerBalanceBefore, expectedUpfront, "Freelancer should receive 20% upfront");
        assertEq(escrow20Bps.getAmountToRelease(), SEND_VALUE - expectedUpfront, "Escrow remainder should match 80%");
    }

    function testFundingWith50PercentBpsSendsExpectedUpfront() public {
        EscrowFreelance escrow50Bps = _deployEscrowWithBps(5000); // 50%
        address client = escrow50Bps.getClientAddress();
        address freelancer = escrow50Bps.getFreelancerAddress();

        vm.deal(client, 5 ether);
        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.prank(client);
        escrow50Bps.fund{value: SEND_VALUE}(SEND_VALUE);

        uint256 expectedUpfront = (SEND_VALUE * 5000) / 10_000;
        assertEq(freelancer.balance - freelancerBalanceBefore, expectedUpfront, "Freelancer should receive 50% upfront");
        assertEq(escrow50Bps.getAmountToRelease(), SEND_VALUE - expectedUpfront, "Escrow remainder should match 50%");
    }

    function testFundingTwiceWith10PercentBpsPaysUpfrontOnlyOnce() public {
        address client = escrowWithBPS.getClientAddress();
        address freelancer = escrowWithBPS.getFreelancerAddress();

        vm.deal(client, 10 ether);
        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.startPrank(client);
        escrowWithBPS.fund{value: SEND_VALUE}(SEND_VALUE);
        escrowWithBPS.fund{value: SEND_VALUE}(SEND_VALUE);
        vm.stopPrank();

        uint256 expectedUpfrontOnce = (SEND_VALUE * BPS) / 10_000;
        assertEq(
            freelancer.balance - freelancerBalanceBefore, expectedUpfrontOnce, "Upfront payment must be sent only once"
        );
        assertEq(
            escrowWithBPS.getAmountToRelease(),
            (SEND_VALUE - expectedUpfrontOnce) + SEND_VALUE,
            "Second fund should not trigger another upfront payment"
        );
    }

    function _deployEscrowWithBps(uint256 customBps) internal returns (EscrowFreelance) {
        address freelancer = makeAddr("freelancer-custom-bps");
        address admin = makeAddr("admin-custom-bps");
        uint256 deliveryPeriod = 7 days;
        HelperConfig helperConfig = new HelperConfig();

        return new EscrowFreelance(
            msg.sender, freelancer, deliveryPeriod, helperConfig.activeNetworkConfig(), address(0), admin, customBps
        );
    }
}
