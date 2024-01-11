// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {IFactory} from "./interfaces/IFactory.sol";

library GasMagicPlugin {
    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error UnsupportedChain(uint256 chainId);
    error HttpError(uint256 error);
    error NotEffectiveAction();
    error NotEffectiveCompression();
    error InvalidSalt();
    error DeployError();

    enum DEPLOY_KIND {
        CREATE2,
        CREATE
    }

    struct Response {
        uint256 efficiency;
        bytes encoded;
        string status;
    }

    function getFactory() internal returns (IFactory) {
        address addr = _factoryAddress(block.chainid);
        if (addr == address(0)) revert UnsupportedChain(block.chainid);
        return IFactory(addr);
    }

    function getFactory(address factory) internal returns (IFactory) {
        return IFactory(factory);
    }

    function _factoryAddress(uint256 chainid) internal returns (address factory) {
        if (chainid == 1) {
            revert NotEffectiveAction();
        } else if (chainid == 10) {
            factory = address(0);
        } else if (chainid == 31337) {
            factory = address(0x3133700000000000000000000000000000000002);
            if (factory.code.length == 0) {
                address feeManager = address(0x313370000000000000000000000000000000000F);
                address decompressor = address(0x3133700000000000000000000000000000000001);

                vm.etch(factory, vm.readFileBinary("var/factory.bin"));
                vm.etch(feeManager, vm.readFileBinary("var/feeManager.bin"));
                vm.etch(decompressor, vm.readFileBinary("var/decompressor.bin"));

                vm.store(factory, bytes32(uint256(0)), bytes32(uint256(uint160(decompressor))));
                vm.store(factory, bytes32(uint256(1)), bytes32(uint256(uint160(feeManager))));
            }
        }

        return factory;
    }

    // @notice: forked from <https://github.com/memester-xyz/surl>
    function curl(string memory url, string[] memory headers, string memory body, string memory method)
        internal
        returns (uint256 status, bytes memory data)
    {
        string memory scriptStart = 'response=$(curl -s -w "\\n%{http_code}" ';
        string memory scriptEnd =
            '); status=$(tail -n1 <<< "$response"); data=$(sed "$ d" <<< "$response");data=$(echo "$data" | tr -d "\\n"); cast abi-encode "response(uint256,string)" "$status" "$data";';

        string memory curlParams = "";

        for (uint256 i = 0; i < headers.length; i++) {
            curlParams = string.concat(curlParams, '-H "', headers[i], '" ');
        }

        curlParams = string.concat(curlParams, " -X ", method, " ");

        if (bytes(body).length > 0) {
            curlParams = string.concat(curlParams, " -d \'", body, "\' ");
        }

        string memory quotedURL = string.concat('"', url, '"');

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(scriptStart, curlParams, quotedURL, scriptEnd, "");
        bytes memory res = vm.ffi(inputs);

        (status, data) = abi.decode(res, (uint256, bytes));
    }

    function encode(bytes memory input) public returns (bytes memory) {
        if (block.chainid == 31337) {
            return input;
        }

        string[] memory headers = new string[](1);
        headers[0] = "Content-Type: application/json";

        (uint256 status, bytes memory data) =
            curl(vm.envString("ENCODER_API_URL"), headers, vm.serializeBytes("request", "data", input), "POST");
        if (status != 200) revert HttpError(status);
        bytes memory parsed = vm.parseJson(string(data));
        Response memory r = abi.decode(parsed, (Response));
        if (r.efficiency == 0) revert NotEffectiveCompression();

        return r.encoded;
    }

    function getCreateAddress(address deployer, bytes32 codeHash) public returns (address addr, uint256 l1GasCost) {
        IFactory factory = getFactory();
        return factory.getCreateAddress(deployer, codeHash);
    }

    function getCreate2Address(bytes32 codeHash, uint96 salt) public returns (address addr, uint256 l1GasCost) {
        IFactory factory = getFactory();
        return factory.getCreate2Address(codeHash, salt);
    }

    function bruteSalt(bytes32 codeHash) external returns (address, uint96, uint256) {
        return _bruteSalt(1e5, codeHash);
    }

    function bruteSalt(uint256 iterations, bytes32 codeHash)
        external
        returns (address, uint96, uint256)
    {
        return _bruteSalt(iterations, codeHash);
    }

    // @notice: for demonstration purpose only: forge using only one CPU core, so computation is slow.
    //          Also, gas limit is not infinity.
    // @notice: for best performance use OpenCL GPU generator. E.g. <https://github.com/0age/create2crunch>
    // @dev: 1e6 iterations can brute 3 zero-bytes for ~30 seconds
    function _bruteSalt(uint256 iterations, bytes32 codeHash)
        private
        returns (address addr, uint96 salt, uint256 l1GasCost)
    {
        l1GasCost = 320; // initial value for 20 non-zero bytes according <https://eips.ethereum.org/EIPS/eip-1559>
        uint256 start = vm.unixTime();
        uint256 end = vm.unixTime() + iterations;
        for (uint256 i = start; i <= end;) {
            uint96 salt_ = uint96(i);
            (address addr_, uint256 cost_) = getCreate2Address(codeHash, salt_);
            if (cost_ < l1GasCost) {
                addr = addr_;
                salt = salt_;
                l1GasCost = cost_;
            }
            unchecked {
                ++i;
            }
        }
    }

    function deploy(bytes memory input, DEPLOY_KIND kind) internal returns (address) {
        bytes memory bytecode = encode(input);
        return _deploy(bytecode, kind, uint96(0));
    }

    function deploy(bytes memory input, DEPLOY_KIND kind, uint96 salt) internal returns (address) {
        bytes memory bytecode = encode(input);
        return _deploy(bytecode, kind, salt);
    }

    function deploy(bytes memory input, DEPLOY_KIND kind, bytes memory constructorArgs) internal returns (address) {
        bytes memory bytecode = encode(abi.encodePacked(input, constructorArgs));
        return _deploy(bytecode, kind, uint96(0));
    }

    function deploy(bytes memory input, DEPLOY_KIND kind, uint96 salt, bytes memory constructorArgs)
        internal
        returns (address)
    {
        bytes memory bytecode = encode(abi.encodePacked(input, constructorArgs));
        return _deploy(bytecode, kind, salt);
    }

    function _constructCall(bytes memory compressedBytecode) internal view returns(bytes memory){
        return abi.encodePacked(IFactory.DEPLOY_KIND.CREATE, compressedBytecode);
    }

    function _constructCall(uint96 salt, bytes memory compressedBytecode) internal view returns(bytes memory){
        return abi.encodePacked(IFactory.DEPLOY_KIND.CREATE2, salt, compressedBytecode);
    }

    function _deploy(bytes memory input, DEPLOY_KIND kind, uint96 salt) private returns (address addr) {
        IFactory factory = getFactory();
        uint256 fee = factory.calculateFee(input);
        if (kind == DEPLOY_KIND.CREATE) {
            if (salt != 0) revert InvalidSalt();
            (bool success, bytes memory res) = address(factory).call(
                _constructCall(input)
            );
            addr = abi.decode(res, (address));
        } else if (kind == DEPLOY_KIND.CREATE2) {
            if (salt == 0) revert InvalidSalt();
            (bool success, bytes memory res) = address(factory).call(
                _constructCall(salt, input)
            );
            addr = abi.decode(res, (address));
        }
        if (addr == address(0)) revert DeployError();
    }
}
