// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@/Test.sol";
import "../src/GasMagicPlugin.sol";

contract Dull {
    fallback() external {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, and(address(), 0xffffffffffffffffffffffffffffffffffffffff))
            return(ptr, 0x20)
        }
    }
}

contract DullWithConstructor {
    constructor(address, bool) payable {}

    fallback() external {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, and(address(), 0xffffffffffffffffffffffffffffffffffffffff))
            return(ptr, 0x20)
        }
    }
}

contract GasMagicPluginT is Test {
    IFactory public factory;

    receive() external payable {}

    function setUp() external {
        factory = GasMagicPlugin.getFactory();
    }

    function _checkDull(address dull) internal {
        (bool success, bytes memory res) = dull.call("");
        assertTrue(success, "fallback corrupted");
        address returnValue = abi.decode(res, (address));
        assertEq(returnValue, dull);
    }

    function test_create1() external {
        for (uint256 i; i < 5; i++) {
            (address precalculated, uint256 l1GasCost) =
                GasMagicPlugin.getCreateAddress(address(this), keccak256(type(Dull).creationCode));
            address deployed = GasMagicPlugin.deploy(type(Dull).creationCode, GasMagicPlugin.DEPLOY_KIND.CREATE);
            assertEq(deployed, precalculated);
            _checkDull(deployed);
        }
    }

    function test_create2() external {
        for (uint256 i = 1; i <= 5; i++) {
            uint96 salt = uint96(i);
            (address precalculated, uint256 l1GasCost) =
                GasMagicPlugin.getCreate2Address(keccak256(type(Dull).creationCode), salt);
            address deployed = GasMagicPlugin.deploy(type(Dull).creationCode, GasMagicPlugin.DEPLOY_KIND.CREATE2, salt);
            assertEq(deployed, precalculated);
            _checkDull(deployed);
        }
    }

    function test_createWithArgs() external {
        for (uint256 i = 1; i <= 5; i++) {
            bytes memory args = abi.encode(address(this), true);
            (address precalculated, uint256 l1GasCost) = GasMagicPlugin.getCreateAddress(
                address(this), keccak256(abi.encodePacked(type(DullWithConstructor).creationCode, args))
            );
            address deployed =
                GasMagicPlugin.deploy(type(DullWithConstructor).creationCode, GasMagicPlugin.DEPLOY_KIND.CREATE, args);
            assertEq(deployed, precalculated);
            _checkDull(deployed);
        }
    }

    function _deploySalted(bytes memory initCode, uint96 salt, address expected) internal {
        (address precalculated, uint256 l1GasCost) = factory.getCreate2Address(keccak256(initCode), salt);
        bytes memory compressed = GasMagicPlugin.encode(initCode);
        uint256 fee = factory.calculateFee(compressed);
        address deployed =
            GasMagicPlugin.deploy(initCode, GasMagicPlugin.DEPLOY_KIND.CREATE2, salt);
        assertEq(deployed, precalculated);
        assertEq(deployed, expected);
    }

    function test_fuzzBruteSalt() external {
        (address addr, uint96 salt, uint256 l1GasCost) =
            GasMagicPlugin.bruteSalt(1e5, keccak256(type(Dull).creationCode));
        _deploySalted(type(Dull).creationCode, salt, addr);
    }

    function test_CREATE2CRUNCH() external {
        assertEq(
            keccak256(type(Dull).creationCode),
            bytes32(0xb3baaad88c8b2051dfd3423b66eef1d55c801c50011da8e8db188e2155fd1105)
        );
        _deploySalted(
            type(Dull).creationCode,
            uint96(uint256(0x43d1f3475d8154512c000020)),
            0xB00000818A96AcA7B900FD1de93041460CA7dEEb
        );
    }
}
