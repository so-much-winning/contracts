/**
 *  The Consumer Contract Wallet
 *  Copyright (C) 2018 Token Group Ltd
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.

 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.

 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity ^0.4.25;

import "./licence.sol";
import "./internals/ownable.sol";
import "./internals/controllable.sol";
import "./internals/ensable.sol";
import "./internals/tokenWhitelistable.sol";
import "./externals/ens/PublicResolver.sol";
import "./externals/SafeMath.sol";
import "./externals/ERC20.sol";
import "./externals/ERC165.sol";


/// @title Whitelist provides payee-whitelist functionality.
/// @dev This contract will allow the user to maintain a whitelist of addresses
/// @dev These addresses will live outside of the various spend limits
contract Whitelist is Controllable, Ownable {
    event AddedToWhitelist(address _sender, address[] _addresses);
    event SubmittedWhitelistAddition(address[] _addresses, bytes32 _hash);
    event CancelledWhitelistAddition(address _sender, bytes32 _hash);

    event RemovedFromWhitelist(address _sender, address[] _addresses);
    event SubmittedWhitelistRemoval(address[] _addresses, bytes32 _hash);
    event CancelledWhitelistRemoval(address _sender, bytes32 _hash);

    mapping(address => bool) public isWhitelisted;
    address[] private _pendingWhitelistAddition;
    address[] private _pendingWhitelistRemoval;
    bool public submittedWhitelistAddition;
    bool public submittedWhitelistRemoval;
    bool public initializedWhitelist;

    /// @dev Check if the provided addresses contain the owner or the zero-address address.
    modifier hasNoOwnerOrZeroAddress(address[] _addresses) {
        for (uint i = 0; i < _addresses.length; i++) {
            require(_addresses[i] != owner(), "provided whitelist contains the owner address");
            require(_addresses[i] != address(0), "provided whitelist contains the zero address");
        }
        _;
    }

    /// @dev Check that neither addition nor removal operations have already been submitted.
    modifier noActiveSubmission() {
        require(!submittedWhitelistAddition && !submittedWhitelistRemoval, "whitelist operation has already been submitted");
        _;
    }

    /// @dev Getter for pending addition array.
    function pendingWhitelistAddition() external view returns (address[]) {
        return _pendingWhitelistAddition;
    }

    /// @dev Getter for pending removal array.
    function pendingWhitelistRemoval() external view returns (address[]) {
        return _pendingWhitelistRemoval;
    }

    /// @dev Add initial addresses to the whitelist.
    /// @param _addresses are the Ethereum addresses to be whitelisted.
    function initializeWhitelist(address[] _addresses) external onlyOwner hasNoOwnerOrZeroAddress(_addresses) {
        // Require that the whitelist has not been initialized.
        require(!initializedWhitelist, "whitelist has already been initialized");
        // Add each of the provided addresses to the whitelist.
        for (uint i = 0; i < _addresses.length; i++) {
            isWhitelisted[_addresses[i]] = true;
        }
        initializedWhitelist = true;
        // Emit the addition event.
        emit AddedToWhitelist(msg.sender, _addresses);
    }

    /// @dev Add addresses to the whitelist.
    /// @param _addresses are the Ethereum addresses to be whitelisted.
    function submitWhitelistAddition(address[] _addresses) external onlyOwner noActiveSubmission hasNoOwnerOrZeroAddress(_addresses) {
        // Require that the whitelist has been initialized.
        require(initializedWhitelist, "whitelist has not been initialized");
        // Require this array of addresses not empty
        require(_addresses.length > 0, "pending whitelist addition is empty");
        // Set the provided addresses to the pending addition addresses.
        _pendingWhitelistAddition = _addresses;
        // Flag the operation as submitted.
        submittedWhitelistAddition = true;
        // Emit the submission event.
        emit SubmittedWhitelistAddition(_addresses, calculateHash(_addresses));
    }

    /// @dev Confirm pending whitelist addition.
    /// @dev This will only ever be applied post 2FA, by one of the Controllers
    /// @param _hash is the hash of the pending whitelist array, a form of lamport lock
    function confirmWhitelistAddition(bytes32 _hash) external onlyController {
        // Require that the whitelist addition has been submitted.
        require(submittedWhitelistAddition, "whitelist addition has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist addition match
        require(_hash == calculateHash(_pendingWhitelistAddition), "hash of the pending whitelist addition do not match");
        // Whitelist pending addresses.
        for (uint i = 0; i < _pendingWhitelistAddition.length; i++) {
            isWhitelisted[_pendingWhitelistAddition[i]] = true;
        }
        // Emit the addition event.
        emit AddedToWhitelist(msg.sender, _pendingWhitelistAddition);
        // Reset pending addresses.
        delete _pendingWhitelistAddition;
        // Reset the submission flag.
        submittedWhitelistAddition = false;
    }

    /// @dev Cancel pending whitelist addition.
    function cancelWhitelistAddition(bytes32 _hash) external onlyController {
        // Check if operation has been submitted.
        require(submittedWhitelistAddition, "whitelist addition has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist addition match
        require(_hash == calculateHash(_pendingWhitelistAddition), "hash of the pending whitelist addition does not match");
        // Reset pending addresses.
        delete _pendingWhitelistAddition;
        // Reset the submitted operation flag.
        submittedWhitelistAddition = false;
        // Emit the cancellation event.
        emit CancelledWhitelistAddition(msg.sender, _hash);
    }

    /// @dev Remove addresses from the whitelist.
    /// @param _addresses are the Ethereum addresses to be removed.
    function submitWhitelistRemoval(address[] _addresses) external onlyOwner noActiveSubmission {
        // Require that the whitelist has been initialized.
        require(initializedWhitelist, "whitelist has not been initialized");
        // Require this array of addresses not empty
        require(_addresses.length > 0, "pending whitelist removal is empty");
        // Add the provided addresses to the pending addition list.
        _pendingWhitelistRemoval = _addresses;
        // Flag the operation as submitted.
        submittedWhitelistRemoval = true;
        // Emit the submission event.
        emit SubmittedWhitelistRemoval(_addresses, calculateHash(_addresses));
    }

    /// @dev Confirm pending removal of whitelisted addresses.
    function confirmWhitelistRemoval(bytes32 _hash) external onlyController {
        // Require that the pending whitelist is not empty and the operation has been submitted.
        require(submittedWhitelistRemoval, "whitelist removal has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist removal match
        require(_hash == calculateHash(_pendingWhitelistRemoval), "hash of the pending whitelist removal does not match the confirmed hash");
        // Remove pending addresses.
        for (uint i = 0; i < _pendingWhitelistRemoval.length; i++) {
            isWhitelisted[_pendingWhitelistRemoval[i]] = false;
        }
        // Emit the removal event.
        emit RemovedFromWhitelist(msg.sender, _pendingWhitelistRemoval);
        // Reset pending addresses.
        delete _pendingWhitelistRemoval;
        // Reset the submission flag.
        submittedWhitelistRemoval = false;
    }

    /// @dev Cancel pending removal of whitelisted addresses.
    function cancelWhitelistRemoval(bytes32 _hash) external onlyController {
        // Check if operation has been submitted.
        require(submittedWhitelistRemoval, "whitelist removal has not been submitted");
        // Require that confirmation hash and the hash of the pending whitelist removal match
        require(_hash == calculateHash(_pendingWhitelistRemoval), "hash of the pending whitelist removal do not match");
        // Reset pending addresses.
        delete _pendingWhitelistRemoval;
        // Reset pending addresses.
        submittedWhitelistRemoval = false;
        // Emit the cancellation event.
        emit CancelledWhitelistRemoval(msg.sender, _hash);
    }

    /// @dev Method used to hash our whitelist address arrays.
    function calculateHash(address[] _addresses) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_addresses));
    }
}


/// @title DailyLimitTrait This trait allows for daily limits to be included in other contracts.
/// This contract will allow for a DailyLimit object to be instantiated and used.
contract DailyLimitTrait {
    using SafeMath for uint256;

    struct DailyLimit {
        uint limit;
        uint available;
        uint limitDay;

        uint pending;
        bool submitted;
        bool initialized;
    }

    /// @dev Returns the available daily balance - accounts for daily limit reset.
    /// @return amount of available to spend within the current day in wei.
    function _getAvailableLimit(DailyLimit storage dl) internal view returns (uint) {
        if (now > dl.limitDay + 24 hours) {
            return dl.limit;
        } else {
            return dl.available;
        }
    }

    /// @dev Use up amount within the daily limit. Will fail if amount is larger than daily limit.
    function _enforceLimit(DailyLimit storage dl, uint _amount) internal {
        // Account for the spend limit daily reset.
        _updateAvailableLimit(dl);
        require(dl.available >= _amount, "available has to be greater or equal to use amount");
        dl.available = dl.available.sub(_amount);
    }

    /// @dev Initialize a daily limit.
    /// @param _amount is the daily limit amount in wei.
    function _initializeLimit(DailyLimit storage dl, uint _amount) internal {
        // Require that the spend limit has not been initialized.
        require(!dl.initialized, "daily limit has already been initialized");
        // Modify spend limit based on the provided value.
        _modifyLimit(dl, _amount);
        // Flag the operation as initialized.
        dl.initialized = true;
    }

    /// @dev Submit a daily limit change, needs to be confirmed.
    /// @param _amount is the daily limit amount in wei.
    function _submitLimitUpdate(DailyLimit storage dl, uint _amount) internal {
        // Require that the spend limit has been initialized.
        require(dl.initialized, "limit has not been initialized");
        // Require that the operation has been submitted.
        require(!dl.submitted, "limit has already been submitted");
        // Assign the provided amount to pending daily limit change.
        dl.pending = _amount;
        // Flag the operation as submitted.
        dl.submitted = true;
    }

    /// @dev Confirm pending set daily limit operation.
    function _confirmLimitUpdate(DailyLimit storage dl, uint _amount) internal {
        // Require that the operation has been submitted.
        require(dl.submitted, "limit has not been submitted");
        // Require that pending and confirmed spend limit are the same
        require(dl.pending == _amount, "confirmed and submitted limits dont match");
        // Modify spend limit based on the pending value.
        _modifyLimit(dl, dl.pending);
        // Reset the submission flag.
        dl.submitted = false;
        // Reset pending daily limit.
        dl.pending = 0;
    }

    /// @dev Cancel pending set daily limit operation.
    function _cancelLimitUpdate(DailyLimit storage dl, uint _amount) internal {
        // Check if there has been a limit update submitted
        require(dl.submitted, "limit update not submitted");
        // Require that pending and confirmed spend limit are the same
        require(dl.pending == _amount, "confirmed and cancelled limits dont match");
        // Reset pending daily limit.
        dl.pending = 0;
        // Reset the submitted operation flag.
        dl.submitted = false;
    }

    /// @dev Update available spend limit based on the daily reset.
    function _updateAvailableLimit(DailyLimit storage dl) private {
        if (now > dl.limitDay.add(24 hours)) {
            // Advance the current day by how many days have passed.
            uint extraDays = now.sub(dl.limitDay).div(24 hours);
            dl.limitDay = dl.limitDay.add(extraDays.mul(24 hours));
            // Set the available limit to the current spend limit.
            dl.available = dl.limit;
        }
    }

    /// @dev Modify the spend limit and spend available based on the provided value.
    /// @dev _amount is the daily limit amount in wei.
    function _modifyLimit(DailyLimit storage dl, uint _amount) private {
        // Account for the spend limit daily reset.
        _updateAvailableLimit(dl);
        // Set the daily limit to the provided amount.
        dl.limit = _amount;
        // Lower the available limit if it's higher than the new daily limit.
        if (dl.available > dl.limit) {
            dl.available = dl.limit;
        }
    }
}


//// @title SpendLimit provides daily spend limit functionality.
contract SpendLimit is Controllable, Ownable, DailyLimitTrait {
    event SetSpendLimit(address _sender, uint _amount);
    event SubmittedSpendLimitUpdate(uint _amount);
    event CancelledSpendLimitUpdate(address _sender, uint _amount);

    DailyLimit internal _spendLimit;

    /// @dev Constructor initializes the daily spend limit in wei.
    constructor(uint _limit) internal {
        _spendLimit = DailyLimit(_limit, _limit, now, 0, false, false);
    }

    function _spendLimitProxyConstructor(uint _limit) {
        _spendLimit = DailyLimit(_limit, _limit, now, 0, false, false);
    }

    /// @dev Initialize a daily spend (aka transfer) limit for non-whitelisted addresses.
    /// @param _amount is the daily limit amount in wei.
    function initializeSpendLimit(uint _amount) external onlyOwner {
        _initializeLimit(_spendLimit, _amount);
        emit SetSpendLimit(msg.sender, _amount);
    }

    /// @dev Set a daily transfer limit for non-whitelisted addresses.
    /// @param _amount is the daily limit amount in wei.
    function submitSpendLimitUpdate(uint _amount) external onlyOwner {
        _submitLimitUpdate(_spendLimit, _amount);
        emit SubmittedSpendLimitUpdate(_amount);
    }

    /// @dev Confirm pending set daily limit operation.
    function confirmSpendLimitUpdate(uint _amount) external onlyController {
        _confirmLimitUpdate(_spendLimit, _amount);
        emit SetSpendLimit(msg.sender, _amount);
    }

    /// @dev Cancel pending set daily limit operation.
    function cancelSpendLimitUpdate(uint _amount) external onlyController {
        _cancelLimitUpdate(_spendLimit, _amount);
        emit CancelledSpendLimitUpdate(msg.sender, _amount);
    }

    function spendAvailable() public view returns (uint) {
        return _getAvailableLimit(_spendLimit);
    }

    function spendLimit() public view returns (uint) {
        return _spendLimit.limit;
    }

    function initializedSpendLimit() public view returns (bool) {
        return _spendLimit.initialized;
    }

    function submittedSpendLimit() public view returns (bool) {
        return _spendLimit.submitted;
    }

    function pendingSpendLimit() public view returns (uint) {
        return _spendLimit.pending;
    }
}


//// @title GasTopUpLimit provides daily  limit functionality.
contract GasTopUpLimit is Controllable, Ownable, DailyLimitTrait {

    event SetGasTopUpLimit(address _sender, uint _amount);
    event SubmittedGasTopUpLimitUpdate(uint _amount);
    event CancelledGasTopUpLimitUpdate(address _sender, uint _amount);

    uint constant private _MINIMUM_GAS_TOPUP_LIMIT = 1 finney;
    uint constant private _MAXIMUM_GAS_TOPUP_LIMIT = 500 finney;

    DailyLimit internal _gasTopUpLimit;

    /// @dev Constructor initializes the daily spend limit in wei.
    constructor() internal {
        _gasTopUpLimit = DailyLimit(_MAXIMUM_GAS_TOPUP_LIMIT, _MAXIMUM_GAS_TOPUP_LIMIT, now, 0, false, false);
    }

    function _gasTopupProxyConstructor() internal {
        _gasTopUpLimit = DailyLimit(_MAXIMUM_GAS_TOPUP_LIMIT, _MAXIMUM_GAS_TOPUP_LIMIT, now, 0, false, false);
    }

    /// @dev Initialize a daily gas top up limit.
    /// @param _amount is the top up gas amount in wei.
    function initializeGasTopUpLimit(uint _amount) external onlyOwner {
        require(_MINIMUM_GAS_TOPUP_LIMIT <= _amount && _amount <= _MAXIMUM_GAS_TOPUP_LIMIT, "gas top up amount is outside the min/max range");
        _initializeLimit(_gasTopUpLimit, _amount);
        emit SetGasTopUpLimit(msg.sender, _amount);
    }

    /// @dev Set a daily top up gas limit.
    /// @param _amount is the daily top up gas limit amount in wei.
    function submitGasTopUpLimitUpdate(uint _amount) external onlyOwner {
        require(_MINIMUM_GAS_TOPUP_LIMIT <= _amount && _amount <= _MAXIMUM_GAS_TOPUP_LIMIT, "gas top up amount is outside the min/max range");
        _submitLimitUpdate(_gasTopUpLimit, _amount);
        emit SubmittedGasTopUpLimitUpdate(_amount);
    }

    /// @dev Confirm pending set top up gas limit operation.
    function confirmGasTopUpLimitUpdate(uint _amount) external onlyController {
        _confirmLimitUpdate(_gasTopUpLimit, _amount);
        emit SetGasTopUpLimit(msg.sender, _amount);
    }

    /// @dev Cancel pending set top up gas limit operation.
    function cancelGasTopUpLimitUpdate(uint _amount) external onlyController {
        _cancelLimitUpdate(_gasTopUpLimit, _amount);
        emit CancelledGasTopUpLimitUpdate(msg.sender, _amount);
    }

    function gasTopUpLimit() public view returns (uint) {
        return _gasTopUpLimit.limit;
    }

    function gasTopUpAvailable() public view returns (uint) {
        return _getAvailableLimit(_gasTopUpLimit);
    }

    function initializedGasTopUpLimit() public view returns (bool) {
        return _gasTopUpLimit.initialized;
    }

    function submittedGasTopUpLimit() public view returns (bool) {
        return _gasTopUpLimit.submitted;
    }

    function pendingGasTopUpLimit() public view returns (uint) {
        return _gasTopUpLimit.pending;
    }
}


/// @title LoadLimit provides daily Load limit functionality.
contract LoadLimit is Controllable, Ownable, DailyLimitTrait {

    event SetLoadLimit(address _sender, uint _amount);
    event SubmittedLoadLimitUpdate(uint _amount);
    event CancelledLoadLimitUpdate(address _sender, uint _amount);

    uint constant private _MINIMUM_LOAD_LIMIT = 1 finney;
    uint constant private _MAXIMUM_LOAD_LIMIT = 101 ether;

    DailyLimit internal _loadLimit;

    /// @dev Constructor initializes the daily spend limit in wei.
    constructor() internal {
        _loadLimit = DailyLimit(_MAXIMUM_LOAD_LIMIT, _MAXIMUM_LOAD_LIMIT, now, 0, false, false);
    }

    function _loadLimitProxyConstructor() internal {
        _loadLimit = DailyLimit(_MAXIMUM_LOAD_LIMIT, _MAXIMUM_LOAD_LIMIT, now, 0, false, false);
    }



    /// @dev Initialize a daily card load limit.
    /// @param _amount is the card load amount in wei.
    function initializeLoadLimit(uint _amount) external onlyOwner {
        require(_MINIMUM_LOAD_LIMIT <= _amount && _amount <= _MAXIMUM_LOAD_LIMIT, "card load amount is outside the min/max range");
        _initializeLimit(_loadLimit, _amount);
        emit SetLoadLimit(msg.sender, _amount);
    }

    /// @dev Set a daily load limit.
    /// @param _amount is the daily load limit amount in wei.
    function submitLoadLimitUpdate(uint _amount) external onlyOwner {
        require(_MINIMUM_LOAD_LIMIT <= _amount && _amount <= _MAXIMUM_LOAD_LIMIT, "card load amount is outside the min/max range");
        _submitLimitUpdate(_loadLimit, _amount);
        emit SubmittedLoadLimitUpdate(_amount);
    }

    /// @dev Confirm pending set load limit operation.
    function confirmLoadLimitUpdate(uint _amount) external onlyController {
        _confirmLimitUpdate(_loadLimit, _amount);
        emit SetLoadLimit(msg.sender, _amount);
    }

    /// @dev Cancel pending set load limit operation.
    function cancelLoadLimitUpdate(uint _amount) external onlyController {
        _cancelLimitUpdate(_loadLimit, _amount);
        emit CancelledLoadLimitUpdate(msg.sender, _amount);
    }

    function loadLimit() public view returns (uint) {
        return _loadLimit.limit;
    }

    function loadAvailable() public view returns (uint) {
        return _getAvailableLimit(_loadLimit);
    }

    function initializedLoadLimit() public view returns (bool) {
        return _loadLimit.initialized;
    }

    function submittedLoadLimit() public view returns (bool) {
        return _loadLimit.submitted;
    }

    function pendingLoadLimit() public view returns (uint) {
        return _loadLimit.pending;
    }
}


//// @title Asset store with extra security features.
contract Vault is Whitelist, SpendLimit, ERC165, TokenWhitelistable {

    using SafeMath for uint256;

    event Received(address _from, uint _amount);
    event Transferred(address _to, address _asset, uint _amount);

    /// @dev Supported ERC165 interface ID.
    bytes4 private constant _ERC165_INTERFACE_ID = 0x01ffc9a7; // solium-disable-line uppercase

    /// @dev Constructor initializes the vault with an owner address and spend limit. It also sets up the oracle and controller contracts.
    /// @param _owner is the owner account of the wallet contract.
    /// @param _transferable indicates whether the contract ownership can be transferred.
    /// @param _tokenWhitelistName is the ENS name of the Token whitelist.
    /// @param _controllerName is the ENS name of the controller.
    /// @param _spendLimit is the initial spend limit.
    constructor(address _owner, bool _transferable, bytes32 _tokenWhitelistName, bytes32 _controllerName, uint _spendLimit) SpendLimit(_spendLimit) Ownable(_owner, _transferable) Controllable(_controllerName) TokenWhitelistable(_tokenWhitelistName) public {
    }

    function _vaultProxyConstructor(address _owner, bool _transferable, bytes32 _tokenWhitelistName, bytes32 _controllerName, uint _spendLimit) public {
      _spendLimitProxyConstructor(_spendLimit);
      _ownableProxyConstructor(_owner, _transferable);
      _controllableProxyConstructor(_controllerName);
      _tokenWhitelistableProxyConstructor(_tokenWhitelistName);
    }

    /// @dev Checks if the value is not zero.
    modifier isNotZero(uint _value) {
        require(_value != 0, "provided value cannot be zero");
        _;
    }

    /// @dev Ether can be deposited from any source, so this contract must be payable by anyone.
    function() public payable {
        require(msg.data.length == 0, "msg data needs to be empty");
        emit Received(msg.sender, msg.value);
    }

    /// @dev Returns the amount of an asset owned by the contract.
    /// @param _asset address of an ERC20 token or 0x0 for ether.
    /// @return balance associated with the wallet address in wei.
    function balance(address _asset) external view returns (uint) {
        if (_asset != address(0)) {
            return ERC20(_asset).balanceOf(this);
        } else {
            return address(this).balance;
        }
    }

    /// @dev Transfers the specified asset to the recipient's address.
    /// @param _to is the recipient's address.
    /// @param _asset is the address of an ERC20 token or 0x0 for ether.
    /// @param _amount is the amount of assets to be transferred in base units.
    function transfer(address _to, address _asset, uint _amount) external onlyOwner isNotZero(_amount) {
        // Checks if the _to address is not the zero-address
        require(_to != address(0), "_to address cannot be set to 0x0");

        // If address is not whitelisted, take daily limit into account.
        if (!isWhitelisted[_to]) {
            //initialize ether value in case the asset is ETH
            uint etherValue = _amount;
            // Convert token amount to ether value if asset is an ERC20 token.
            if (_asset != address(0)) {
                etherValue = convert(_asset, _amount);
            }
            // Check against the daily spent limit and update accordingly
            // Check against the daily spent limit and update accordingly, require that the value is under remaining limit.
            _enforceLimit(_spendLimit, etherValue);
        }
        // Transfer token or ether based on the provided address.
        if (_asset != address(0)) {
            require(ERC20(_asset).transfer(_to, _amount), "ERC20 token transfer was unsuccessful");
        } else {
            _to.transfer(_amount);
        }
        // Emit the transfer event.
        emit Transferred(_to, _asset, _amount);
    }

    /// @dev Checks for interface support based on ERC165.
    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        return interfaceID == _ERC165_INTERFACE_ID;
    }

    /// @dev Convert ERC20 token amount to the corresponding ether amount (used by the wallet contract).
    /// @param _token ERC20 token contract address.
    /// @param _amount amount of token in base units.
    function convert(address _token, uint _amount) public view returns (uint) {
        // Store the token in memory to save map entry lookup gas.
        ( , uint256 magnitude, uint256 rate, bool available, , ) = _getTokenInfo(_token);
        // If the token exists require that its rate is not zero
        if (available) {
            require(rate != 0, "token rate is 0");
            // Safely convert the token amount to ether based on the exchange rate.
            // return the value, the token is, AT LEAST, protected
            return _amount.mul(rate).div(magnitude);
        }
        // this returns a 0/'false' to imply that the token is not protected
        return 0;
    }
}

contract Upgradeable {
    address public codeAddress;

    function upgrade(address _newAddress) {
        codeAddress = _newAddress;
    }
}

/// @title Proxy - Generic proxy contract allows to execute all transactions applying the code of a master contract.
/// @author Stefan George - <stefan@gnosis.pm>
contract ProxyWallet {

    // masterCopy always needs to be first declared variable, to ensure that it is at the same location in the contracts to which calls are delegated.
    // To reduce deployment costs this variable is internal and needs to be retrieved via `getStorageAt`
    address internal masterCopy;

    /// @dev Constructor function sets address of master copy contract.
    /// @param _masterCopy Master copy address.
    constructor(address _masterCopy, address _owner, bool _transferable, address _ens, bytes32 _oracleName, bytes32 _controllerName, bytes32 _licenceName, uint _spendLimit) public {
        require(_masterCopy != address(0), "Invalid master copy address provided");
        masterCopy = _masterCopy;
        require(masterCopy.delegatecall(abi.encodeWithSignature("_proxyConstructor(address,bool,address,bytes32,bytes32,bytes32,uint256)", _owner, _transferable, _ens, _oracleName, _controllerName, _licenceName, _spendLimit)), "must call constructor");
    }

    /// @dev Fallback function forwards all transactions and returns all received return data.
    function () external payable {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let masterCopy := and(sload(0), 0xffffffffffffffffffffffffffffffffffffffff)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas, masterCopy, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

//// @title Asset wallet with extra security features, gas top up management and card integration.
contract Wallet is Upgradeable, ENSable, Vault, GasTopUpLimit, LoadLimit {

    event ToppedUpGas(address _sender, address _owner, uint _amount);
    event LoadedTokenCard(address _asset, uint _amount);

    /// @dev Is the registered ENS name of the oracle contract.
    bytes32 private _licenceNode;

    /// @dev Constructor initializes the wallet top up limit and the vault contract.
    /// @param _owner is the owner account of the wallet contract.
    /// @param _transferable indicates whether the contract ownership can be transferred.
    /// @param _ens is the address of the ENS.
    /// @param _oracleName is the ENS name of the Oracle.
    /// @param _controllerName is the ENS name of the Controller.
    /// @param _licenceName is the ENS name of the licence.
    /// @param _spendLimit is the initial spend limit.
    constructor(address _owner, bool _transferable, address _ens, bytes32 _oracleName, bytes32 _controllerName, bytes32 _licenceName, uint _spendLimit) ENSable(_ens) Vault(_owner, _transferable, _oracleName, _controllerName, _spendLimit) public {
        _licenceNode = _licenceName;
    }

    function _proxyConstructor(address _owner, bool _transferable, address _ens, bytes32 _oracleName, bytes32 _controllerName, bytes32 _licenceName, uint _spendLimit) external {
      _ensableProxyConstructor(_ens);
      _vaultProxyConstructor(_owner, _transferable, _oracleName, _controllerName, _spendLimit);
      _gasTopupProxyConstructor();
      _loadLimitProxyConstructor();
      _licenceNode = _licenceName;
    }

    /// @dev Refill owner's gas balance, revert if the transaction amount is too large
    /// @param _amount is the amount of ether to transfer to the owner account in wei.
    function topUpGas(uint _amount) external isNotZero(_amount) {
        // Require that the sender is either the owner or a controller.
        require(_isOwner() || _isController(msg.sender), "sender is neither an owner nor a controller");
        // Check against the daily spent limit and update accordingly, require that the value is under remaining limit.
        _enforceLimit(_gasTopUpLimit, _amount);
        // Then perform the transfer
        owner().transfer(_amount);
        // Emit the gas top up event.
        emit ToppedUpGas(msg.sender, owner(), _amount);
    }

    /// @dev Load a token card with the specified asset amount.
    /// @dev the amount send should be inclusive of the percent licence.
    /// @param _asset is the address of an ERC20 token or 0x0 for ether.
    /// @param _amount is the amount of assets to be transferred in base units.
    function loadTokenCard(address _asset, uint _amount) external payable onlyOwner {
        // Get the TKN licenceAddress from ENS
        address licenceAddress = PublicResolver(_ENS.resolver(_licenceNode)).addr(_licenceNode);

        if (_asset != address(0)) {
            //check if token is allowed to be used for loading the card
            require(_isTokenLoadable(_asset), "token not loadable");
            // Convert token amount to ether value.
            uint etherValue = convert(_asset, _amount);
            // Check against the daily spent limit and update accordingly, require that the value is under remaining limit.
            _enforceLimit(_loadLimit, etherValue);
            require(ERC20(_asset).approve(licenceAddress, _amount), "ERC20 token approval was unsuccessful");
            ILicence(licenceAddress).load(_asset, _amount);
        } else {
            //_amount is in wei, require that the value is under remaining limit.
            _enforceLimit(_loadLimit, _amount);
            ILicence(licenceAddress).load.value(_amount)(_asset, _amount);
        }

        emit LoadedTokenCard(_asset, _amount);
    }
}
