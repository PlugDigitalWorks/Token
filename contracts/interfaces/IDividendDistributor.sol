// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDividendDistributor {
    function deposit() external payable;
    function process(uint256 gas) external;
    function setShare(address shareholder, uint256 amount) external;
}