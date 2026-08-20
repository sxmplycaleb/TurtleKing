/// Calculates a user's age from their date of birth and compares against a
/// configurable age threshold.
///
/// Age is calculated accurately, accounting for whether the birthday has
/// occurred this year. This is a pure utility — no Flutter or UI dependency.
class AgeCalculator {
  const AgeCalculator._();

  /// The default minimum age for TurtleKing (18+).
  static const int defaultMinimumAge = 18;

  /// Calculates the exact age of a person born on [dob] as of [today].
  ///
  /// Returns `null` if [dob] is after [today] (future DOB) or if [dob] is
  /// null.
  ///
  /// The calculation accounts for whether the birthday has occurred this year:
  /// - Birthday already passed → age = currentYear - birthYear
  /// - Birthday not yet reached → age = currentYear - birthYear - 1
  /// - Birthday is today → age = currentYear - birthYear
  static int? calculateAge(DateTime? dob, {DateTime? today}) {
    if (dob == null) return null;

    final now = today ?? DateTime.now();

    // Future DOB is invalid.
    if (dob.isAfter(now)) return null;

    var age = now.year - dob.year;

    // Check if the birthday has occurred this year.
    // If the birthday month is after the current month, subtract 1.
    // If the birthday month is the same, check the day.
    if (now.month < dob.month) {
      age--;
    } else if (now.month == dob.month && now.day < dob.day) {
      age--;
    }

    return age;
  }

  /// Returns `true` if the given [age] meets the [minimumAge] threshold.
  static bool isEligible(int? age, {int minimumAge = defaultMinimumAge}) {
    if (age == null) return false;
    return age >= minimumAge;
  }

  /// Returns `true` if the [dob] represents a valid, non-future date.
  static bool isValidDob(DateTime? dob, {DateTime? today}) {
    if (dob == null) return false;
    final now = today ?? DateTime.now();
    return !dob.isAfter(now);
  }

  /// Calculates the latest DOB that makes a person exactly [minimumAge]
  /// years old as of [today].
  ///
  /// The result is `today - minimumAge years`, handling month/day rollover.
  /// For example, if today is 20 August 2026 and minimumAge is 18, the
  /// result is 20 August 2008.
  ///
  /// This is the maximum selectable DOB in the date picker — any date
  /// after this would make the user younger than [minimumAge].
  static DateTime maxEligibleDate({
    DateTime? today,
    int minimumAge = defaultMinimumAge,
  }) {
    final now = today ?? DateTime.now();
    return DateTime(now.year - minimumAge, now.month, now.day);
  }

  /// Calculates a sensible default DOB approximately [defaultYearsAgo]
  /// years in the past, clamped to not exceed [maxEligibleDate].
  ///
  /// This ensures the default is always within the valid selectable range
  /// even if the calculated date falls after the maximum.
  static DateTime defaultDob({
    DateTime? today,
    int minimumAge = defaultMinimumAge,
    int defaultYearsAgo = 25,
  }) {
    final now = today ?? DateTime.now();
    final maxDate = maxEligibleDate(today: now, minimumAge: minimumAge);
    final preferred = DateTime(now.year - defaultYearsAgo, now.month, now.day);
    // If the preferred date is after the max (e.g. defaultYearsAgo < minimumAge
    // or unusual date math), clamp to the max.
    return preferred.isAfter(maxDate) ? maxDate : preferred;
  }
}
