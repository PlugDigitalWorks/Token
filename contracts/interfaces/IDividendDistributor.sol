// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDividendDistributor {
    function deposit() external payable;
    function process() external;
    function setShare(address shareholder, uint256 amount) external;
}