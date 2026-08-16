import Foundation

enum RESTJSONSchemaValidator {
    static func validate(_ value: Any, schema: JSONSchema, schemas: [String: JSONSchema], field: String) throws {
        if value is NSNull {
            guard schema.nullable == true else { throw RESTCLIError.invalidFieldType(field) }
            return
        }
        if let reference = schema.ref {
            guard let resolved = schemas[reference] else {
                throw RESTCLIError.invalidRequest("Request schema reference is unavailable: \(reference)")
            }
            return try validate(value, schema: resolved, schemas: schemas, field: field)
        }
        if let type = schema.type, !matches(value, type) { throw RESTCLIError.invalidFieldType(field) }
        switch value {
        case let object as [String: Any]:
            let properties = schema.properties ?? [:]
            if !properties.isEmpty {
                for key in object.keys where properties[key] == nil {
                    throw RESTCLIError.unknownField("\(field).\(key)")
                }
            }
            for key in schema.required ?? [] where object[key] == nil || object[key] is NSNull {
                throw RESTCLIError.missingField("\(field).\(key)")
            }
            for (key, child) in object where !(child is NSNull) {
                guard let childSchema = properties[key] else { continue }
                try validate(child, schema: childSchema, schemas: schemas, field: "\(field).\(key)")
            }
        case let values as [Any]:
            if let minimum = schema.minItems, values.count < minimum { throw RESTCLIError.invalidFieldType(field) }
            if let maximum = schema.maxItems, values.count > maximum { throw RESTCLIError.invalidFieldType(field) }
            if let itemSchema = schema.items?.schema {
                for (index, item) in values.enumerated() {
                    try validate(item, schema: itemSchema, schemas: schemas, field: "\(field)[\(index)]")
                }
            }
        case let text as String:
            if let minimum = schema.minLength, text.count < minimum { throw RESTCLIError.invalidFieldType(field) }
            if let maximum = schema.maxLength, text.count > maximum { throw RESTCLIError.invalidFieldType(field) }
            if let choices = schema.enumValues, !choices.contains(text) { throw RESTCLIError.invalidFieldType(field) }
            if let pattern = schema.pattern,
               text.range(of: pattern, options: .regularExpression) == nil { throw RESTCLIError.invalidFieldType(field) }
        case let number as NSNumber where !(value is Bool):
            if let minimum = schema.minimum, number.doubleValue < minimum { throw RESTCLIError.invalidFieldType(field) }
            if let maximum = schema.maximum, number.doubleValue > maximum { throw RESTCLIError.invalidFieldType(field) }
        default:
            break
        }
    }

    private static func matches(_ value: Any, _ type: JSONType) -> Bool {
        switch type {
        case .object: value is [String: Any]
        case .array: value is [Any]
        case .string: value is String
        case .integer:
            value is NSNumber && !(value is Bool) && (value as! NSNumber).doubleValue.rounded() == (value as! NSNumber).doubleValue
        case .number: value is NSNumber && !(value is Bool)
        case .boolean: value is Bool
        case .nullValue: value is NSNull
        }
    }
}
