# The executable specification file, written in Gherkin: https://cucumber.io/docs/gherkin/reference/

Feature: Single Span Ingestion Control
  Scenario: The trace is dropped
    Given the trace is dropped
    And DD_SPAN_SAMPLING_RULES is set to
    """
      {"service": "greenhouse", "name": "rack.request", "max_per_second": 1000}
    ]'
    """
    And a span for service "greenhouse" and name "rack.request"
    When I sample the span
    Then the _dd.span_sampling metrics should be
    """
    _dd.span_sampling.mechanism=8
    _dd.span_sampling.rule_rate=1.0
    _dd.span_sampling.limit_rate=1.0
    """

  Scenario: The trace is kept
    Given the trace is kept
    And DD_SPAN_SAMPLING_RULES is set to
    """
      {"service": "greenhouse", "name": "rack.request", "max_per_second": 1000}
    ]'
    """
    And a span for service "greenhouse" and name "rack.request"
    When I sample the span
    Then the _dd.span_sampling metrics should be
    """
    """

