public enum CloudBatchBudget {
    public static let maximumUploadEvents = 50
    public static let maximumPullEvents = 200
    public static let maximumBytes = 16 * 1_024 * 1_024
    public static func canInclude(count: Int, bytes: Int, nextBytes: Int, eventLimit: Int = maximumUploadEvents) -> Bool {
        count >= 0 && count < eventLimit && bytes >= 0 && bytes <= maximumBytes
            && nextBytes >= 0 && nextBytes <= maximumBytes - bytes
    }
}
