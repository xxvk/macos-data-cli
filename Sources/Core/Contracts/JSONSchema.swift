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
    public let pattern: String?
    public let minLength: Int?
    public let maxLength: Int?
    public let minimum: Double?
    public let maximum: Double?
    public let minItems: Int?
    public let maxItems: Int?
    public let nullable: Bool?
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
        pattern: String? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        nullable: Bool? = nil,
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
        self.pattern = pattern
        self.minLength = minLength
        self.maxLength = maxLength
        self.minimum = minimum
        self.maximum = maximum
        self.minItems = minItems
        self.maxItems = maxItems
        self.nullable = nullable
        self.additionalProperties = additionalProperties
        self.example = example
    }

    enum CodingKeys: String, CodingKey {
        case type, title, description, properties, required, items, format, pattern
        case minLength, maxLength, minimum, maximum, minItems, maxItems, nullable
        case additionalProperties, example
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
    func requiring(_ names: [String]) -> JSONSchema {
        JSONSchema(
            type: type, title: title, description: description, properties: properties,
            required: names, items: items, ref: ref, enumValues: enumValues,
            format: format, pattern: pattern, minLength: minLength, maxLength: maxLength,
            minimum: minimum, maximum: maximum, minItems: minItems, maxItems: maxItems,
            nullable: nullable, additionalProperties: additionalProperties, example: example
        )
    }

    public static func object(
        title: String? = nil,
        description: String? = nil,
        properties: [String: JSONSchema],
        required: [String] = []
    ) -> JSONSchema {
        JSONSchema(type: .object, title: title, description: description, properties: properties, required: required)
    }

    public static func array(of items: JSONSchema, minItems: Int? = nil, maxItems: Int? = nil) -> JSONSchema {
        JSONSchema(type: .array, items: JSONSchemaBox(items), minItems: minItems, maxItems: maxItems)
    }

    public static func string(
        _ description: String? = nil,
        format: String? = nil,
        pattern: String? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        nullable: Bool? = nil,
        example: JSONValue? = nil
    ) -> JSONSchema {
        JSONSchema(
            type: .string,
            description: description,
            format: format,
            pattern: pattern,
            minLength: minLength,
            maxLength: maxLength,
            nullable: nullable,
            example: example
        )
    }

    public static func integer(
        _ description: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        example: JSONValue? = nil
    ) -> JSONSchema {
        JSONSchema(type: .integer, description: description, minimum: minimum, maximum: maximum, example: example)
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
