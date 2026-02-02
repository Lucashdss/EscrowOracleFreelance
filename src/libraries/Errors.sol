//SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

library Errors {
    error OnlyClient();
    error OnlyFreelancer();
    error InvalidState();
    error DeliveryPeriodNotOver();
    error DeliverNotConfirmed();
    error TransferFailed();
    error InsufficientFunds();
    error NotPerformUpkeep();
    error ContractHasBeenAlreadyFunded();
    error ContractHasBeenAlreadyReleasedOrRefunded();
    error AmountIsInferiorToMinimumUSD();
    error TokenAddressIsNotETH();
    error TokenAddressIsNotERC20();
}
