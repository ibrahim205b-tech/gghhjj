/// Injectable clock so business logic is testable and never calls
/// DateTime.now() directly.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FixedClock implements Clock {
  DateTime current;
  FixedClock(this.current);
  @override
  DateTime now() => current;
  void advance(Duration d) => current = current.add(d);
}
