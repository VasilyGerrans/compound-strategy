pragma solidity ^0.8.10;

interface IPriceOracle {
    function getUnderlyingPrice(address) external view returns (uint);
}