package app.andromac

object Otp {
    private val keyword = Regex("(?i)\\b(otp|one[- ]time|verification|verify|code|passcode|pin|password|authenticate|login|security)\\b")
    private val digits = Regex("(?<![\\d.])(\\d{4,8})(?![\\d])")
    private val dashed = Regex("(?<!\\d)(\\d{3})[ -](\\d{3})(?!\\d)")
    private val alnum = Regex("(?i)\\b(?:G-)?(\\d{6})\\b")

    /** Returns a likely OTP/code or null. Needs a keyword so we don't grab amounts or dates. */
    fun extract(text: String): String? {
        if (!keyword.containsMatchIn(text)) return null
        dashed.find(text)?.let { return it.groupValues[1] + it.groupValues[2] }
        // ignore currency amounts like "Rs 5000" / "INR 1200.50"
        val cleaned = text.replace(Regex("(?i)(rs\\.?|inr|₹|usd|\\$)\\s*[\\d,]+(\\.\\d+)?"), " ")
        return digits.find(cleaned)?.groupValues?.get(1) ?: alnum.find(cleaned)?.groupValues?.get(1)
    }
}
