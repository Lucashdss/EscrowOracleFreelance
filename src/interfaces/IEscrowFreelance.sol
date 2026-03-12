// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEscrowFreelance {
    function canAutoProcess() external view returns (bool);
    function autoProcess() external;
}
