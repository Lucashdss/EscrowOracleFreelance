// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EscrowFreelance} from "./EscrowFreelance.sol";

contract EscrowFreelanceFactory {
    event EscrowCreated(
        address indexed escrowAddress,
        address indexed client,
        address indexed freelancer,
        address token,
        uint256 deliveryPeriod,
        address dataFeed,
        uint256 bps
    );

    function createEscrow(
        address freelancer,
        uint256 deliveryPeriod,
        address dataFeed,
        address token,
        address admin,
        uint256 bps
    ) external returns (address escrow) {
        EscrowFreelance instance = new EscrowFreelance(
            freelancer,
            deliveryPeriod,
            dataFeed,
            token,
            admin,
            bps
        );
        escrow = address(instance);
        emit EscrowCreated(
            escrow,
            msg.sender,
            freelancer,
            token,
            deliveryPeriod,
            dataFeed,
            bps
        );
    }
}
