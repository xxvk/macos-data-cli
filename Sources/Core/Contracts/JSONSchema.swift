import Foundation

/// A JSON Schema document, restricted to the subset needed to describe CLI
/// payloads to agent tooling and documentation renderers. It is faithful enough
/// for DSH tool schemas and Scalar-style views, and small enough to hand-author
/// for the core payload types until Codable reflection replaces it.
public struct JSONSchema: Codable, Sendable {
    public let type: JSONType?
    public let title: String?
    public let description: String?
    public let properties: [String: JSONSchema]?
    public let required: [String]?
    public let items: JSONSchemaBox?
    public let ref: String?
    public let enumValues: [String]?
    public let format: String?
    public let additionalProperties: Bool?
    public let example: JSONValue?

    public init(
        type: JSONType? = nil,
        title: String? = nil,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        items: JSONSchemaBox? = nil,
        ref: String? = nil,
        enumValues: [String]? = nil,
        format: String? = nil,
        additionalProperties: Bool? = nil,
        example: JSONValue? = nil
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items
        self.ref = ref
        self.enumValues = enumValues
        self.format = format
        self.additionalProperties = additionalProperties
        self.example = example
    }

    enum CodingKeys: String, CodingKey {
        case type, title, description, properties, required, items, format, additionalProperties, example
        case ref = "$ref"
        case enumValues = "enum"
    }
}

/// Heap box that breaks the recursive value-type cycle for `JSONSchema.items`.
/// `Optional<JSONSchema>` would otherwise store the struct inline and recurse
/// infinitely; a reference-typed box stores only a pointer.
public final class JSONSchemaBox: Codable, @unchecked Sendable {
    public let schema: JSONSchema
    public init(_ schema: JSONSchema) { self.schema = schema }
    public init(from decoder: Decoder) throws { schema = try JSONSchema(from: decoder) }
    public func encode(to encoder: Encoder) throws { try schema.encode(to: encoder) }
}

public enum JSONType: String, Codable, Sendable {
    case object
    case array
    case string
    case integer
    case number
    case boolean
    case nullValue = "null"
}

extension JSONSchema {
    public static func object(
        title: String? = nil,
        description: String? = nil,
        properties: [String: JSONSchema],
        required: [String] = []
    ) -> JSONSchema {
        JSONSchema(type: .object, title: title, description: description, properties: properties, required: required)
    }

    public static func array(of items: JSONSchema) -> JSONSchema {
        JSONSchema(type: .array, items: JSONSchemaBox(items))
    }

    public static func string(_ description: String? = nil, format: String? = nil, example: JSONValue? = nil) -> JSONSchema {
        JSONSchema(type: .string, description: description, format: format, example: example)
    }

    public static func integer(_ description: String? = nil, example: JSONValue? = nil) -> JSONSchema {
        JSONSchema(type: .integer, description: description, example: example)
    }

    public static func number(_ description: String? = nil, example: JSONValue? = nil) -> JSONSchema {
        JSONSchema(type: .number, description: description, example: example)
    }

    public static func boolean(_ description: String? = nil, example: JSONValue? = nil) -> JSONSchema {
        JSONSchema(type: .boolean, description: description, example: example)
    }

    public static func stringEnum(_ values: [String], description: String? = nil) -> JSONSchema {
        JSONSchema(type: .string, description: description, enumValues: values)
    }

    public static func ref(_ name: String) -> JSONSchema {
        JSONSchema(ref: name)
    }

    public static let anyString = JSONSchema.string()
}
