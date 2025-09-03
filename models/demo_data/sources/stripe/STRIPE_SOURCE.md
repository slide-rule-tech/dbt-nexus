# Stripe Source Documentation

This directory contains the source models for processing Stripe webhook data in
the Nexus demo environment.

## Overview

The Stripe source models process invoice and payment webhook events to extract
customer data, payment information, and subscription details for identity
resolution and event tracking.

## Data Sources

### Demo Data Seeds

- `stripe_invoices_raw_demo.csv` - Sample Stripe invoice webhook events
- `stripe_payments_raw_demo.csv` - Sample Stripe payment intent webhook events

## Models

### Base Models

Located in `/base/` directory:

#### `stripe_invoices_base.sql`

Processes Stripe invoice webhook events including:

- Invoice creation and payment events
- Customer information extraction
- Amount and currency details
- Subscription relationships
- Event deduplication based on latest occurrence

#### `stripe_payments_base.sql`

Processes Stripe payment intent webhook events including:

- Payment success events
- Billing details and customer information
- Card and payment method details
- Risk assessment data
- Billing address information

### Event Models

#### `stripe_events.sql`

Unified event stream combining:

- Invoice events (creation, payment)
- Payment events (successful payments)
- Standardized event values and descriptions

### Identity Resolution Models

#### Person Identifiers

- `stripe_person_identifiers.sql` - Extracts email addresses from customer data

#### Group Identifiers

- `stripe_group_identifiers.sql` - Extracts customer IDs, subscription IDs, and
  invoice IDs

#### Membership Identifiers

- `stripe_membership_identifiers.sql` - Links customers (groups) to their email
  addresses (persons)

#### Person Traits

- `stripe_person_traits.sql` - Customer personal information (name, email,
  phone)

#### Group Traits

- `stripe_group_traits.sql` - Customer account information (payment status,
  subscription details, payment methods)

## Key Features

### Event Processing

- Real-time event filtering using `real_time_event_filter` macro
- Event deduplication to ensure latest data
- Standardized event naming and descriptions

### Customer Data Extraction

- Email domain analysis (generic vs internal domains)
- Test account identification
- Comprehensive customer profile building

### Payment Processing

- Amount conversion from cents to dollars
- Risk assessment integration
- Payment method and card details
- Billing address normalization

### Identity Resolution

- Email-based person identification
- Customer ID-based group identification
- Subscription and invoice relationship mapping

## Data Flow

1. **Raw Data**: Webhook events stored in seed files
2. **Base Models**: Extract and standardize data from JSON payloads
3. **Event Models**: Create unified event streams
4. **Identity Models**: Extract identifiers, traits, and relationships for Nexus
   processing

## Configuration

All models are configured with:

- `materialized='table'` for performance
- Appropriate tags for filtering and organization
- Real-time processing capabilities

## Usage

These models feed into the broader Nexus identity resolution system, providing:

- Customer event tracking
- Payment and subscription analytics
- Identity graph construction
- Customer journey analysis

The Stripe source integrates seamlessly with other sources (Gmail, Google
Calendar, Gadget) to provide a comprehensive view of customer interactions and
business events.
