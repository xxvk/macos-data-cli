public enum PhotoError: Error, Equatable, Sendable, CustomStringConvertible {
    case permissionRequired
    case permissionDenied
    case permissionRestricted
    case assetNotFound(String)
    case invalidDateRange
    case invalidLimit
    case invalidIdentifier
    case invalidArgument(String)
    case exportVariantUnavailable
    case exportVariantAmbiguous
    case outputExists
    case invalidOutput
    case contentNotLocal
    case exportFailed
    case readFailed(String)

    public var machineCode: String {
        switch self {
        case .permissionRequired: "PHOTOS_PERMISSION_REQUIRED"
        case .permissionDenied: "PHOTOS_PERMISSION_DENIED"
        case .permissionRestricted: "PHOTOS_PERMISSION_RESTRICTED"
        case .assetNotFound: "PHOTOS_ASSET_NOT_FOUND"
        case .invalidDateRange: "PHOTOS_INVALID_DATE_RANGE"
        case .invalidLimit: "PHOTOS_INVALID_LIMIT"
        case .invalidIdentifier: "PHOTOS_INVALID_IDENTIFIER"
        case .invalidArgument: "PHOTOS_INVALID_ARGUMENT"
        case .exportVariantUnavailable: "PHOTOS_EXPORT_VARIANT_UNAVAILABLE"
        case .exportVariantAmbiguous: "PHOTOS_EXPORT_VARIANT_AMBIGUOUS"
        case .outputExists: "PHOTOS_OUTPUT_EXISTS"
        case .invalidOutput: "PHOTOS_INVALID_OUTPUT"
        case .contentNotLocal: "PHOTOS_CONTENT_NOT_LOCAL"
        case .exportFailed: "PHOTOS_EXPORT_FAILED"
        case .readFailed: "PHOTOS_READ_FAILED"
        }
    }

    public var description: String {
        switch self {
        case .permissionRequired:
            "Photos permission has not been granted. Run 'mpia photos permission --request'."
        case .permissionDenied:
            "Photos permission was denied. Enable access in System Settings > Privacy & Security > Photos."
        case .permissionRestricted:
            "Photos access is restricted by macOS or device policy."
        case .assetNotFound:
            "The photo asset was not found, is outside limited access, or its opaque ID is stale."
        case .invalidDateRange:
            "Photos query requires start to be earlier than end and within the supported range."
        case .invalidLimit:
            "Photos limit must be between 1 and 200."
        case .invalidIdentifier:
            "The Photos opaque identifier is invalid."
        case .invalidArgument(let message):
            "Invalid Photos argument: \(message)"
        case .exportVariantUnavailable:
            "The requested Photos resource variant is unavailable for this asset."
        case .exportVariantAmbiguous:
            "The requested Photos resource variant has multiple candidates; export refuses to guess."
        case .outputExists:
            "The Photos export destination already exists; overwrite is not allowed."
        case .invalidOutput:
            "The Photos export destination must have an existing writable parent directory."
        case .contentNotLocal:
            "The Photos resource is not available locally. Retry only with explicit --allow-network approval."
        case .exportFailed:
            "Photos could not export the selected resource. No partial output was kept."
        case .readFailed(let message):
            "Unable to read Photos metadata: \(message)"
        }
    }
}
