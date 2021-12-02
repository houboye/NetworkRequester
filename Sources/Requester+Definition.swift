
public let RequestValidationErrorDomain = "com.example.request.validation"
public let RequestValidationErrorInvalidStatusCode = -8
public let RequestValidationErrorInvalidJSONFormat = -9

/// HTTP Request method.
public enum RequestMethod: Int {
    case get = 0
    case post = 1
    case head = 2
    case put = 3
    case delete = 4
    case patch = 5
}

///  Response serializer type, which determines response serialization process and
///  the type of `responseObject`.
public enum ResponseSerializerType {
    /// NSData type
    case data
    /// JSON object type
    case json
    /// NSXMLParser type
    case xmlParser
}

public enum RequestPriority {
    case low
    case `default`
    case high
}

public enum RequestParameterEncoder {
    case urlDefault
    case urlQueryString
    case urlHttpBody
    case jsonDefault
    case jsonPrettyPrinted
}
