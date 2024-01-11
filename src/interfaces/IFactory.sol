// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFactory {
    error Unauthorized();
    error DeployFailed();
    error InsufficientFeePaid();
    error NotEffectiveAction();

    enum DEPLOY_KIND {
        CREATE2,
        CREATE
    }

    function getCreateAddress(address deployer, bytes32 codeHash)
        external
        view
        returns (address addr, uint256 l1GasCost);
    function getCreate2Address(bytes32 codeHash, uint96 salt)
        external
        view
        returns (address addr, uint256 l1GasCost);

    function create(bytes calldata) external payable returns (address);
    function create2(bytes calldata, uint96) external payable returns (address);

    function calculateFee(bytes calldata compressedBytecode) external view returns (uint256);
}
