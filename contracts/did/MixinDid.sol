// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

import "../interface/IDid.sol";
import "./MixinDidStorage.sol";
import "../libs/DidUtils.sol";
import "../libs/KeyUtils.sol";
import "../libs/BytesUtils.sol";
import "../libs/ZeroCopySink.sol";
import "../libs/ZeroCopySource.sol";
import "../libs/StorageUtils.sol";

/**
 * @title DIDContract
 * @dev This contract is did logic implementation
 */
contract DIDContract is MixinDidStorage, IDid {

    modifier didActivated(string memory did){
        require(!didStatus[BytesUtils.toLower(did)].deactivated, "did is deactivated");
        _;
    }

    modifier notSelfAddr(string memory did, address addr){
        address didAddr = DidUtils.parseAddrFromDID(bytes(did));
        require(didAddr != addr, "no need to add self addr");
        _;
    }

    /**
    * @dev require all did formats are legal
    */
    modifier verifyMultiDIDFormat(string[] memory dids){
        for (uint i = 0; i < dids.length; i++) {
            require(DidUtils.verifyDIDFormat(dids[i]),
                "verify did format failed");
        }
        _;
    }

    /**
    * @dev require msg.sender must be did,
    * it means public key of msg.sender must be one of did authentication
    */
    modifier requireDIDSign(string memory did, bytes memory signerPubKey) {
        require(verifySignature(did, signerPubKey), "verify did signature failed");
        _;
    }

    modifier requireDIDControllerSign(string memory did, string memory controller, bytes memory signerPubKey){
        require(verifyController(did, controller, signerPubKey), "verify did controller signature failed");
        _;
    }

    constructor() public {

    }

    /**
   * @dev deactivate did, delete all document data of this did, but record did has been registered,
   *    it means this did cannot been registered in the future
   * @param did did
   */
    function deactivateID(string memory did, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey) didActivated(did)
    override public {
        did = BytesUtils.toLower(did);
        require(!didStatus[did].deactivated, "did is deactivated");
        // delete context
        delete data[KeyUtils.genContextKey(did)];
        // delete public key list
        delete data[KeyUtils.genPubKeyListKey(did)];
        // delete controller
        delete data[KeyUtils.genControllerKey(did)];
        // delete service
        delete data[KeyUtils.genServiceKey(did)];
        // delete update time
        delete data[KeyUtils.genUpdateTimeKey(did)];
        // update status
        didStatus[did].deactivated = true;
        didStatus[did].authListLen = 0;
        emit Deactivate(did);
    }

    /**
   * @dev add a new public key to did public key list only, the key doesn't enter authentication list
   * @param did did
   * @param newPubKey new public key
   * @param controller controller of newPubKey, they are some did
   */
    function addKey(string memory did, bytes memory newPubKey, string[] memory controller,
        bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey) verifyMultiDIDFormat(controller)
    override public {
        addNewPubKey(did, newPubKey, address(0), "EcdsaSecp256k1VerificationKey2019", controller, true, false);
        emit AddKey(did, newPubKey, controller);
    }

    /**
    * @dev add a new address to did public key list only, the key doesn't enter authentication list
    * @param did did
    * @param addr new address
    * @param controller controller of newPubKey, they are some did
    */
    function addAddr(string memory did, address addr, string[] memory controller, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey) verifyMultiDIDFormat(controller) notSelfAddr(did, addr)
    override public {
        bytes memory emptyPubKey = new bytes(0);
        addNewPubKey(did, emptyPubKey, addr, "EcdsaSecp256k1RecoveryMethod2020", controller, true, false);
        emit AddAddr(did, addr, controller);
    }

    /**
   * @dev add a new public key to authentication list only, doesn't enter public key list
   * @param did did
   * @param pubKey the new public key
   * @param controller controller of newPubKey, they are some did
   */
    function addNewAuthKey(string memory did, bytes memory pubKey, string[] memory controller,
        bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey) verifyMultiDIDFormat(controller)
    override public {
        addNewPubKey(did, pubKey, address(0), "EcdsaSecp256k1VerificationKey2019", controller,
            false, true);
        emit AddNewAuthKey(did, pubKey, controller);
    }

    /**
   * @dev add a new address to authentication list only, doesn't enter public key list
   * @param did did
   * @param addr the new address
   * @param controller controller of newPubKey, they are some did
   */
    function addNewAuthAddr(string memory did, address addr, string[] memory controller,
        bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey) verifyMultiDIDFormat(controller) notSelfAddr(did, addr)
    override public {
        bytes memory emptyPubKey = new bytes(0);
        addNewPubKey(did, emptyPubKey, addr, "EcdsaSecp256k1RecoveryMethod2020", controller, false, true);
        emit AddNewAuthAddr(did, addr, controller);
    }

    /**
   * @dev controller add a new public key to authentication list only, doesn't enter public key list
   * @param did did
   * @param pubKey the new public key
   * @param controller controller of newPubKey, they are some did
   * @param controllerSigner tx signer should be one of did controller
   */
    function addNewAuthKeyByController(string memory did, bytes memory pubKey, string[] memory controller,
        string memory controllerSigner, bytes memory signerPubKey)
    requireDIDControllerSign(did, controllerSigner, signerPubKey) verifyMultiDIDFormat(controller)
    override public {
        addNewPubKey(did, pubKey, address(0), "EcdsaSecp256k1VerificationKey2019", controller,
            false, true);
        emit AddNewAuthKey(did, pubKey, controller);
    }

    /**
   * @dev controller add a new address to authentication list only, doesn't enter public key list
   * @param did did
   * @param addr the new address
   * @param controller controller of newPubKey, they are some did
   * @param controllerSigner tx signer should be one of did controller
   */
    function addNewAuthAddrByController(string memory did, address addr, string[] memory controller,
        string memory controllerSigner, bytes memory signerPubKey)
    requireDIDControllerSign(did, controllerSigner, signerPubKey) verifyMultiDIDFormat(controller) notSelfAddr(did, addr)
    override public {
        addNewPubKey(did, new bytes(0), addr, "EcdsaSecp256k1RecoveryMethod2020", controller, false, true);
        emit AddNewAuthAddr(did, addr, controller);
    }

    function addNewPubKey(string memory did, bytes memory pubKey, address addr, string memory keyType,
        string[] memory controller, bool isPub, bool isAuth)
    private {
        require(controller.length >= 1);
        did = BytesUtils.toLower(did);
        uint authIndex = 0;
        if (isAuth) {
            authIndex = fetchAuthIndex(did);
        }
        string memory pubKeyListKey = KeyUtils.genPubKeyListKey(did);
        IterableMapping.itmap storage pubKeyList = data[pubKeyListKey];
        uint keyIndex = pubKeyList.keys.length + 2;
        string memory pubKeyId = string(abi.encodePacked(did, "#keys-", BytesUtils.uint2str(keyIndex)));
        StorageUtils.PublicKey memory pub = StorageUtils.PublicKey(pubKeyId, keyType, controller, pubKey,
            addr, false, isPub, isAuth, authIndex);
        StorageUtils.insertNewPubKey(pubKeyList, pub);
        updateTime(did);
    }

    /**
   * @dev add one key existed in publicKey list to authentication list
   * @param did did
   * @param pubKey public key
   */
    function setAuthKey(string memory did, bytes memory pubKey, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        authPubKey(did, pubKey, address(0));
        emit SetAuthKey(did, pubKey);
    }

    /**
   * @dev add one address existed in publicKey list to authentication list
   * @param did did
   * @param addr address
   */
    function setAuthAddr(string memory did, address addr, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        bytes memory pubKey = new bytes(0);
        authPubKey(did, pubKey, addr);
        emit SetAuthAddr(did, addr);
    }

    /**
   * @dev controller add one key existed in publicKey list to authentication list
   * @param did did
   * @param pubKey public key
   * @param controller one of did controller
   */
    function setAuthKeyByController(string memory did, bytes memory pubKey, string memory controller,
        bytes memory signerPubKey)
    requireDIDControllerSign(did, controller, signerPubKey)
    override public {
        authPubKey(did, pubKey, address(0));
        emit SetAuthKey(did, pubKey);
    }

    /**
   * @dev controller add one address existed in publicKey list to authentication list
   * @param did did
   * @param addr address
   * @param controller one of did controller
   */
    function setAuthAddrByController(string memory did, address addr, string memory controller,
        bytes memory signerPubKey)
    requireDIDControllerSign(did, controller, signerPubKey)
    override public {
        bytes memory pubKey = new bytes(0);
        authPubKey(did, pubKey, addr);
        emit SetAuthAddr(did, addr);
    }

    function authPubKey(string memory did, bytes memory pubKey, address addr) private {
        did = BytesUtils.toLower(did);
        string memory pubKeyListKey = KeyUtils.genPubKeyListKey(did);
        StorageUtils.authPubKey(data[pubKeyListKey], pubKey, addr, fetchAuthIndex(did));
        updateTime(did);
    }

    function fetchAuthIndex(string memory did) private returns (uint){
        uint authIndex = didStatus[did].authListLen + 2;
        // this means each auth key index increased 2 every time
        didStatus[did].authListLen = authIndex;
        return authIndex;
    }

    /**
   * @dev deactivate one key that existed in public key list
   * @param did did
   * @param pubKey public key
   */
    function deactivateKey(string memory did, bytes memory pubKey, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        deactivatePubKey(did, pubKey, address(0));
        emit DeactivateKey(did, pubKey);
    }

    /**
   * @dev deactivate one addr that existed in public key list
   * @param did did
   * @param addr address
   */
    function deactivateAddr(string memory did, address addr, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        bytes memory emptyPubKey = new bytes(0);
        deactivatePubKey(did, emptyPubKey, addr);
        emit DeactivateAddr(did, addr);
    }

    function deactivatePubKey(string memory did, bytes memory pubKey, address addr)
    private {
        did = BytesUtils.toLower(did);
        string memory pubKeyListKey = KeyUtils.genPubKeyListKey(did);
        StorageUtils.deactivatePubKey(data[pubKeyListKey], pubKey, addr);
        updateTime(did);
    }

    /**
   * @dev remove one key from authentication list
   * @param did did
   * @param pubKey public key
   */
    function deactivateAuthKey(string memory did, bytes memory pubKey, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        deAuthPubKey(did, pubKey, address(0));
        emit DeactivateAuthKey(did, pubKey);
    }

    /**
   * @dev remove one address from authentication list
   * @param did did
   * @param addr address
   */
    function deactivateAuthAddr(string memory did, address addr, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        bytes memory pubKey = new bytes(0);
        deAuthPubKey(did, pubKey, addr);
        emit DeactivateAuthAddr(did, addr);
    }

    /**
   * @dev controller remove one key from authentication list
   * @param did did
   * @param pubKey public key
   * @param controller one of did controller
   */
    function deactivateAuthKeyByController(string memory did, bytes memory pubKey, string memory controller,
        bytes memory signerPubKey)
    requireDIDControllerSign(did, controller, signerPubKey)
    override public {
        deAuthPubKey(did, pubKey, address(0));
        emit DeactivateAuthKey(did, pubKey);
    }

    /**
   * @dev controller remove one address from authentication list
   * @param did did
   * @param addr address
   * @param controller one of did controller
   */
    function deactivateAuthAddrByController(string memory did, address addr, string memory controller,
        bytes memory signerPubKey)
    requireDIDControllerSign(did, controller, signerPubKey)
    override public {
        bytes memory pubKey = new bytes(0);
        deAuthPubKey(did, pubKey, addr);
        emit DeactivateAuthAddr(did, addr);
    }

    /**
   * @dev remove public key from authentication list
   * @param did did
   * @param pubKey public key
   */
    function deAuthPubKey(string memory did, bytes memory pubKey, address addr) private {
        did = BytesUtils.toLower(did);
        string memory pubKeyListKey = KeyUtils.genPubKeyListKey(did);
        StorageUtils.deAuthPubKey(data[pubKeyListKey], pubKey, addr);
        updateTime(did);
    }

    /**
   * @dev add context to did document
   * @param did did
   * @param contexts contexts
   */
    function addContext(string memory did, string[] memory contexts, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory ctxKey = KeyUtils.genContextKey(did);
        for (uint i = 0; i < contexts.length; i++) {
            string memory ctx = contexts[i];
            bytes32 key = KeyUtils.genContextSecondKey(ctx);
            bool replaced = data[ctxKey].insert(key, bytes(ctx));
            if (!replaced) {
                emit AddContext(did, ctx);
            }
        }
        updateTime(did);
    }

    /**
   * @dev remove context from did document
   * @param did did
   * @param contexts contexts
   */
    function removeContext(string memory did, string[] memory contexts, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory ctxKey = KeyUtils.genContextKey(did);
        for (uint i = 0; i < contexts.length; i++) {
            string memory ctx = contexts[i];
            bytes32 key = KeyUtils.genContextSecondKey(ctx);
            bool success = data[ctxKey].remove(key);
            if (success) {
                emit RemoveContext(did, ctx);
            }
        }
        updateTime(did);
    }

    /**
   * @dev add one controller to did controller list
   * @param did did
   * @param controller one of did controller
   */
    function addController(string memory did, string memory controller, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory controllerKey = KeyUtils.genControllerKey(did);
        bytes32 key = KeyUtils.genControllerSecondKey(controller);
        bool replaced = data[controllerKey].insert(key, bytes(controller));
        require(!replaced, "controller already existed");
        updateTime(did);
        emit AddController(did, controller);
    }

    /**
   * @dev remove controller from controller list
   * @param did did
   * @param controller one of did controller
   */
    function removeController(string memory did, string memory controller, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory controllerKey = KeyUtils.genControllerKey(did);
        bytes32 key = KeyUtils.genControllerSecondKey(controller);
        bool success = data[controllerKey].remove(key);
        require(success, "controller not existed");
        updateTime(did);
        emit RemoveController(did, controller);
    }

    /**
   * @dev add service to did service list
   * @param did did
   * @param serviceId service id
   * @param serviceType service type
   * @param serviceEndpoint service endpoint
   */
    function addService(string memory did, string memory serviceId, string memory serviceType,
        string memory serviceEndpoint, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory serviceKey = KeyUtils.genServiceKey(did);
        bytes32 key = KeyUtils.genServiceSecondKey(serviceId);
        StorageUtils.Service memory service = StorageUtils.Service(serviceId, serviceType, serviceEndpoint);
        bytes memory serviceBytes = StorageUtils.serializeService(service);
        bool replaced = data[serviceKey].insert(key, serviceBytes);
        require(!replaced, "service already existed");
        updateTime(did);
        emit AddService(did, serviceId, serviceType, serviceEndpoint);
    }

    /**
   * @dev update service
   * @param did did
   * @param serviceId service id
   * @param serviceType service type
   * @param serviceEndpoint service endpoint
   */
    function updateService(string memory did, string memory serviceId, string memory serviceType,
        string memory serviceEndpoint, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory serviceKey = KeyUtils.genServiceKey(did);
        bytes32 key = KeyUtils.genServiceSecondKey(serviceId);
        StorageUtils.Service memory service = StorageUtils.Service(serviceId, serviceType, serviceEndpoint);
        bytes memory serviceBytes = StorageUtils.serializeService(service);
        bool replaced = data[serviceKey].insert(key, serviceBytes);
        require(replaced, "service not existed");
        updateTime(did);
        emit UpdateService(did, serviceId, serviceType, serviceEndpoint);
    }

    /**
   * @dev remove service
   * @param did did
   * @param serviceId service id
   */
    function removeService(string memory did, string memory serviceId, bytes memory signerPubKey)
    requireDIDSign(did, signerPubKey)
    override public {
        did = BytesUtils.toLower(did);
        string memory serviceKey = KeyUtils.genServiceKey(did);
        bytes32 key = KeyUtils.genServiceSecondKey(serviceId);
        bool success = data[serviceKey].remove(key);
        require(success, "service not existed");
        updateTime(did);
        emit RemoveService(did, serviceId);
    }

    /**
   * @dev record did updated time
   * @param did did
   */
    function updateTime(string memory did) private {
        string memory updateTimeKey = KeyUtils.genUpdateTimeKey(did);
        bytes32 key = KeyUtils.genUpdateTimeSecondKey();
        data[updateTimeKey].insert(key, ZeroCopySink.WriteUint255(now));
    }

    /**
   * @dev verify tx has signed by did
   * @param did did
   */
    function verifySignature(string memory did, bytes memory signerPubKey)
    public view returns (bool)
    {
        if (!DidUtils.verifyDIDFormat(did)) {
            return false;
        }
        did = BytesUtils.toLower(did);
        if (didStatus[did].deactivated) {
            return false;
        }
        if (signerPubKey.length > 0) {
            address signer = DidUtils.pubKeyToAddr(signerPubKey);
            require(signer == msg.sender || signer == tx.origin, "signer invalid");
        }
        string memory pubKeyListKey = KeyUtils.genPubKeyListKey(did);
        bytes32 pubKeyListSecondKey = KeyUtils.genPubKeyListSecondKey(signerPubKey, msg.sender);
        if (!data[pubKeyListKey].contains(pubKeyListSecondKey)) {
            return false;
        }
        // if signerPubKey.length > 0, verify signerPubKey is listed in self public key list and authenticated
        // else verify msg.sender is listed in self public key list and authenticated
        StorageUtils.PublicKey memory pub =
        StorageUtils.deserializePubKey(data[pubKeyListKey].data[pubKeyListSecondKey].value);
        return !pub.deactivated && pub.isAuth;
    }

    /**
   * @dev verify tx has signed by did controller
   * @param did did
   * @param controller one of did controller
   */
    function verifyController(string memory did, string memory controller, bytes memory signerPubKey)
    public view returns (bool){
        if (!DidUtils.verifyDIDFormat(did)) {
            return false;
        }
        did = BytesUtils.toLower(did);
        if (didStatus[did].deactivated) {
            return false;
        }
        string memory controllerKey = KeyUtils.genControllerKey(did);
        bytes32 key = KeyUtils.genControllerSecondKey(controller);
        if (!data[controllerKey].contains(key)) {
            return false;
        }
        return verifySignature(controller, signerPubKey);
    }

    /**
   * @dev query public key list
   * @param did did
   */
    function getAllPubKey(string memory did)
    didActivated(did)
    public view returns (StorageUtils.PublicKey[] memory) {
        string memory pubKeyListKey = KeyUtils.genPubKeyListKey(did);
        IterableMapping.itmap storage pubKeyList = data[pubKeyListKey];
        return StorageUtils.getAllPubKey(did, "EcdsaSecp256k1RecoveryMethod2020", pubKeyList);
    }

    /**
   * @dev query authentication list
   * @param did did
   */
    function getAllAuthKey(string memory did)
    didActivated(did)
    public view returns (StorageUtils.PublicKey[] memory) {
        IterableMapping.itmap storage pubKeyList = data[KeyUtils.genPubKeyListKey(did)];
        return StorageUtils.getAllAuthKey(did, "EcdsaSecp256k1RecoveryMethod2020", pubKeyList);
    }

    /**
   * @dev query context list
   * @param did did
   */
    function getContext(string memory did)
    public view returns (string[] memory) {
        string memory ctxListKey = KeyUtils.genContextKey(did);
        IterableMapping.itmap storage ctxList = data[ctxListKey];
        return StorageUtils.getContext(ctxList, "https://www.w3.org/ns/did/v1");
    }

    /**
   * @dev query controller list
   * @param did did
   */
    function getAllController(string memory did)
    public view returns (string[] memory){
        string memory controllerListKey = KeyUtils.genControllerKey(did);
        IterableMapping.itmap storage controllerList = data[controllerListKey];
        return StorageUtils.getAllController(controllerList);
    }

    /**
   * @dev query service list
   * @param did did
   */
    function getAllService(string memory did)
    public view returns (StorageUtils.Service[] memory){
        string memory serviceKey = KeyUtils.genServiceKey(did);
        IterableMapping.itmap storage serviceList = data[serviceKey];
        return StorageUtils.getAllService(serviceList);
    }

    /**
   * @dev query did updated time
   * @param did did
   */
    function getUpdatedTime(string memory did)
    public view returns (uint){
        string memory updateTimeKey = KeyUtils.genUpdateTimeKey(did);
        bytes32 key = KeyUtils.genUpdateTimeSecondKey();
        bytes memory time = data[updateTimeKey].data[key].value;
        if (time.length == 0) {
            return 0;
        }
        (uint256 result,) = ZeroCopySource.NextUint255(time, 0);
        return result;
    }

    /**
   * @dev query document
   * @param did did
   */
    function getDocument(string memory did)
    public view returns (StorageUtils.DIDDocument memory) {
        string[] memory context = getContext(did);
        StorageUtils.PublicKey[] memory publicKey = getAllPubKey(did);
        StorageUtils.PublicKey[] memory authentication = getAllAuthKey(did);
        string[] memory controller = getAllController(did);
        StorageUtils.Service[] memory service = getAllService(did);
        uint updated = getUpdatedTime(did);
        // always set created time as 0
        return StorageUtils.DIDDocument(context, did, publicKey, authentication, controller, service, 0, updated);
    }
}