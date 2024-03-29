//
//  Account.swift
//  Server
//
//  Created by Christopher Prince on 7/9/17.
//

#if os(Linux) || SERVER

import Foundation
import ServerShared
import LoggerAPI
import Kitura
import KituraNet
import HeliumLogger
import Credentials

public protocol UserData {
    var cloudFolderName: String? { get }
    var accountType: AccountScheme.AccountName! { get }
    
    // JSON Credentials
    var creds:String! { get }
    
    var userId: UserId! { get }
}

public enum AccountCreationUser {
    case user(UserData) // use this if we have it.
    case userId(UserId) // and this if we don't.
}

public protocol AccountDelegate : AnyObject {
    // This is delegated because (a) it enables me to only sometimes allow an Account to save to the database, and (b) because knowledge of how to save to a database seems outside of the responsibilities of `Account`s. Returns false iff an error occurred on database save.
    func saveToDatabase(account:Account) -> Bool
}

public protocol AccountHeaders {
    subscript(key: String) -> String? { get }
}

// Account specific properties obtained from a request.
public struct AccountProperties {
    public let accountScheme: AccountScheme
    public let properties: [String: Any]
    
    public init(accountScheme: AccountScheme, properties: [String: Any]) {
        self.accountScheme = accountScheme
        self.properties = properties
    }
}

public protocol Account {
    static var accountScheme:AccountScheme {get}
    var accountScheme:AccountScheme {get}
    
    // Sharing accounts (e.g., Facebook) always need to return false.
    // Owning accounts return true iff they need a cloud folder name (e.g., Google Drive).
    var owningAccountsNeedCloudFolderName: Bool {get}
        
    var accountCreationUser:AccountCreationUser? {get set}
    
    // Currently assuming all Account's use access tokens.
    var accessToken: String! {get set}
    
    // If needed, configuration must abide by type defined by the specific Account.
    init?(configuration: Any?, delegate: AccountDelegate?)
    
    // Optional method. Default implementation always returns true.
    func canCreateAccount(with userProfile: UserProfile) -> Bool
    
    func toJSON() -> String?
    
    /// Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access to that data by sharing users.
    /// You must call this before `generateTokens`-- the Account scheme may save some state as a result of this call that changes how the `generateTokens` call works.
    func needToGenerateTokens(dbCreds:Account?) -> Bool
    
    /// Some Account's (e.g., Google) need to generate internal tokens (e.g., a refresh token) in some circumstances (e.g., when having a serverAuthCode). May use delegate, if one is defined, to save creds to database.
    func generateTokens(completion:@escaping (Swift.Error?)->())
    
    /// Changes `self` to update from the newer account, as needed.
    func merge(withNewer account:Account)

    // Gets account specific properties, if any, from the headers.
    static func getProperties(fromHeaders headers:AccountHeaders) -> [String: Any]
    
    static func fromProperties(_ properties: AccountProperties, user:AccountCreationUser?, configuration: Any?, delegate:AccountDelegate?) -> Account?
    static func fromJSON(_ json:String, user:AccountCreationUser, configuration: Any?, delegate:AccountDelegate?) throws -> Account?
}

public enum FromJSONError : Swift.Error {
    case noRequiredKeyValue
}

public extension Account {
    func canCreateAccount(with userProfile: UserProfile) -> Bool {
        return true
    }
    
    // Only use this for owning accounts.
    var cloudFolderName: String? {
        guard let accountCreationUser = accountCreationUser,
            case .user(let user) = accountCreationUser,
            let cloudFolderName = user.cloudFolderName else {
            
            if owningAccountsNeedCloudFolderName {
                Log.error("Account needs cloud folder name, but has none.")
                assert(false)
            }

            return nil
        }
        
        assert(owningAccountsNeedCloudFolderName)
        return cloudFolderName
    }
    
    func generateTokensIfNeeded(dbCreds:Account?, routerResponse:RouterResponse, success:@escaping ()->(), failure: @escaping ()->()) {
    
        if needToGenerateTokens(dbCreds: dbCreds) {
            generateTokens() { error in
                if error == nil {
                    success()
                }
                else {
                    Log.error("Failed attempting to generate tokens: \(error!))")
                    failure()
                }
            }
        }
        else {
            success()
        }
    }
    
    static func setProperty(jsonDict: [String:Any], key:String, required:Bool=true, setWithValue:(String)->()) throws {
        guard let keyValue = jsonDict[key] as? String else {
            if required {
                Log.error("No \(key) value present: \(jsonDict)")
                throw FromJSONError.noRequiredKeyValue
            }
            else {
                Log.warning("No \(key) value present: \(jsonDict)")
            }
            return
        }

        setWithValue(keyValue)
    }
    
    static var accessTokenKey: String {
        return "accessToken"
    }
    
    static var refreshTokenKey: String {
        return "refreshToken"
    }
}

public enum APICallBody {
    case string(String)
    case data(Data)
}

public enum APICallResult {
    case dictionary([String: Any])
    case array([Any])
    case data(Data)
}

public enum GenerateTokensError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    case nilAPIResult
    case noDataInAPIResult
    case couldNotDecodeResult
    case errorSavingCredsToDatabase
    case couldNotGetSelf
}

// I didn't just use a protocol extension for this because I want to be able to override `apiCall` and call "super" to get the base definition.
open class AccountAPICall {
    // Used by `apiCall` function to make a REST call to an Account service.
    public var baseURL:String?
    
    public init?() {}
    
    private func parseResponse(_ response: ClientResponse, expectedBody: ExpectedResponse?, errorIfParsingFailure: Bool = false) -> APICallResult? {
        var result:APICallResult?

        do {
            var body = Data()
            try response.readAllData(into: &body)

            if let expectedBody = expectedBody, expectedBody == .data {
                result = .data(body)
            }
            else {
                let jsonResult:Any = try JSONSerialization.jsonObject(with: body, options: [])
                
                if let dictionary = jsonResult as? [String : Any] {
                    result = .dictionary(dictionary)
                }
                else if let array = jsonResult as? [Any] {
                    result = .array(array)
                }
                else {
                    result = .data(body)
                }
            }
        } catch (let error) {
            if errorIfParsingFailure {
                Log.error("Failed to read response: \(error)")
            }
        }
        
        return result
    }
    
    public enum ExpectedResponse {
        case data
        case json
    }
    
    // Does an HTTP call to the endpoint constructed by baseURL with path, the HTTP method, and the given body parameters (if any). BaseURL is given without any http:// or https:// (https:// is used). If baseURL is nil, then self.baseURL is used-- which must not be nil in that case.
    // expectingData == true means return Data. false or nil just look for Data or JSON result.
    open func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, additionalOptions: [ClientRequest.Options] = [], urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = true,
                 expectedSuccessBody:ExpectedResponse? = nil,
                 expectedFailureBody:ExpectedResponse? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?, _ responseHeaders: HeadersContainer?)->()) {
        
        var hostname = baseURL
        if hostname == nil {
            hostname = self.baseURL
        }
        
        var requestOptions: [ClientRequest.Options] = additionalOptions
        requestOptions.append(.schema("https://"))
        requestOptions.append(.hostname(hostname!))
        requestOptions.append(.method(method))
        
        if urlParameters == nil {
            requestOptions.append(.path(path))
        }
        else {
            var charSet = CharacterSet.urlQueryAllowed
            // At least for the Google REST API, it seems single quotes need to be encoded. See https://developers.google.com/drive/v3/web/search-parameters
            // urlQueryAllowed doesn't exclude single quotes, so I'm doing that myself.
            charSet.remove("'")
            
            let escapedURLParams = urlParameters!.addingPercentEncoding(withAllowedCharacters: charSet)
            requestOptions.append(.path(path + "?" + escapedURLParams!))
        }
        
        var headers = [String:String]()
        //headers["Accept"] = "application/json; charset=UTF-8"
        headers["Accept"] = "*/*"
        
        if additionalHeaders != nil {
            for (key, value) in additionalHeaders! {
                headers[key] = value
            }
        }
        
        requestOptions.append(.headers(headers))
        
        let req = HTTP.request(requestOptions) {[unowned self] response in
            if let response:KituraNet.ClientResponse = response {
                let statusCode = response.statusCode
                
                if statusCode == HTTPStatusCode.OK {
                    if let result = self.parseResponse(response, expectedBody: expectedSuccessBody, errorIfParsingFailure: true) {
                        completion(result, statusCode, response.headers)
                        return
                    }
                }
                else {                    
                    if returnResultWhenNon200Code {
                        if let result = self.parseResponse(response, expectedBody: expectedFailureBody) {
                            completion(result, statusCode, response.headers)
                        }
                        else {
                            completion(nil, statusCode, nil)
                        }
                        return
                    }
                }
            }
            
            completion(nil, nil, nil)
        }
        
        switch body {
        case .none:
            req.end()
            
        case .some(.string(let str)):
            req.end(str)
            
        case .some(.data(let data)):
            req.end(data)
        }
        
        // Log.debug("Request URL: \(req.url)")
    }
}

#endif
