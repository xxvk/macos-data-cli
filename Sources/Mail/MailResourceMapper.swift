import Core

public enum MailResourceMapper {
    public static func map(
        _ account: MailAccountSummary,
        selected: Bool,
        permission: DataPermissionState = .available,
        displayName: String? = nil
    ) -> DataResource {
        DataResource(
            id: account.id,
            kind: .mailAccount,
            provider: .mail,
            displayName: displayName ?? "Mail account (\(account.kind))",
            capabilities: DataResourceCapabilities(
                readable: permission == .available,
                writable: false,
                selected: selected,
                permission: permission
            )
        )
    }
}
