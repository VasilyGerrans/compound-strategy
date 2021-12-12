pragma solidity ^0.8.10;

interface PriceOracleInterface {
    function getUnderlyingPrice(address) external view returns (uint);
}