# UFC (Universal Flag Configuration) Test Fixtures

This directory contains test fixtures in UFC (Universal Flag Configuration) format.

## What is UFC?

UFC stands for **Universal Flag Configuration**. It's a flexible format for representing feature flag targeting rules using splits with shard ranges and salts. This approach accommodates most targeting use cases and provides a universal way to configure feature flags across different SDKs and platforms.

## Directory Contents

- `flags-v1.json` - Main UFC configuration fixture used across multiple test suites
- `test_cases/` - Individual test cases demonstrating various UFC scenarios including:
  - Boolean, integer, numeric, and string flag variations
  - Targeting rules with different operators (ONE_OF, MATCHES, GTE, etc.)
  - Traffic splitting with shard ranges
  - Edge cases like disabled flags and empty configurations

## Format Overview

The UFC format typically includes:
- **flags**: Feature flag definitions with variations and targeting rules
- **allocations**: Traffic splitting rules with shard-based distribution
- **variations**: Different values a flag can return
- **rules**: Targeting conditions based on user attributes

This format is used consistently across DataDog SDKs to ensure compatible feature flag behavior.