# BigQuery Integration

This document describes the BigQuery integration for MediFlow data archiving.

## Overview

BigQuery is used for long-term storage and analytics of historical data
extracted from Firestore.

## Schema Details

The following tables are created and managed:

- `facilities`: Core facility metadata
- `inventory_snapshots`: Point-in-time inventory states
- `daily_usage_logs`: Aggregated usage patterns for analytics
