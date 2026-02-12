---
title: Real-World Use Cases
tags: [use-cases, applications, operational-data, examples]
summary:
  How dbt-nexus enables operational data use beyond dashboards with real
  examples from SlideRule Analytics
---

# Real-World Use Cases

dbt-nexus isn't just about building better dashboards - it's about making your
data **operationally useful** for sales, support, and growth teams. Here are
real examples of how we use dbt-nexus at SlideRule Analytics.

> Read the full story:
> [**Dbt-Nexus - Data Beyond Dashboards**](/blog/dbt-nexus-data-beyond-dashboards)

## The Problem: Scattered Customer Data

Like most companies, our customer data was spread across many tools:

- Gmail for email communications
- Google Calendar for meetings
- Stripe for payments and subscriptions
- Our Shopify app for usage data
- Google Analytics 4 for attribution

When a customer emailed support, we had to manually search across multiple tools
just to find out how much they were paying us. **This is exactly what dbt-nexus
solves.**

## Complete Customer Timeline

With dbt-nexus, we now have a unified timeline that merges all data sources into
a single view showing everything we know about a customer and their company.

For example, for a customer named Lewis from Hollywood Farms, we can see:

- Emails exchanged with our team (Gmail)
- Invoices and payment history (Stripe)
- Meetings and calls (Google Calendar)
- App usage and setup progress (Custom app data)
- Website analytics and attribution (Google Analytics 4)

All in chronological order, with proper identity resolution connecting Lewis
across all systems.

## Operational Applications

### 1. Timeline App for Support & Sales

We built a lightweight app that reads directly from dbt-nexus tables and shows
events by person, group, and data source.

**Impact**: Support and sales teams can instantly see a customer's complete
history instead of searching multiple tools.

### 2. Daily Updates Email

We get an automated email every day highlighting the most important events that
happened at the company.

**Impact**: Leadership stays informed of key customer activities without manual
reporting.

### 3. Up-to-Date Email Marketing

We push the persons table into Customer.io, ensuring we always have current
email lists with proper segmentation.

**Impact**: Marketing campaigns use up-to-date customer data instead of stale
exports.

### 4. Abandoned Setup Notifications

We automatically detect incomplete app setups and notify our team to reach out
personally.

**Impact**: Improved onboarding completion rates through timely, personalized
outreach.

### 5. AI-Powered Customer Context

We're integrating AI tools with nexus data to provide faster, more personalized
customer interactions.

**Impact**: AI tools have complete customer context for better recommendations
and support.

### 6. Metrics and Dashboards

All our business metrics are built on top of the standardized nexus tables.

**Impact**: Consistent metrics across all reporting tools, faster dashboard
development.

## Why the Data Warehouse?

Many tools promise "360-degree customer views" but fail because they require you
to use their platform for **everything**, **forever** - and nobody does that.

### Advantages of the Data Warehouse Approach:

1. **Full Historical Data**: Pull complete history from any source, not just
   future data
2. **No Vendor Lock-in**: Your data stays under your control
3. **Universal Integration**: Any tool can read from your warehouse
4. **Source Flexibility**: Add or change tools without rebuilding integrations

## Source-Agnostic Design

dbt-nexus works with any data source because it focuses on **structure**
(events, persons, groups) rather than **source**.

### Adding New Sources is Fast:

- **Gmail**: ~1 hour to add email data
- **Google Calendar**: ~1 hour for meeting data
- **Stripe**: ~1 hour for payment events
- **Custom App Data**: ~1 hour per data type

This operational flexibility lets you try new tools without worrying about
lengthy integrations.

## The "Headless CRM" Concept

dbt-nexus functions as a **headless CRM** - providing the data structure and
intelligence of a CRM without forcing you into a specific interface or workflow.

Your teams can:

- Use the tools they prefer
- Access complete customer context anywhere
- Build custom applications on top of clean, structured data
- Integrate with AI and automation tools

## Key Success Factors

### 1. Events as the Foundation

Everything becomes an event with a timestamp, making it easy to answer "what
happened when?" across any data source.

### 2. Identity Resolution

Graph-based algorithms stitch together identifiers (email, phone, user ID)
across sources to create unified person and group profiles.

### 3. Timeline-Based Thinking

Focus on **when** things happened, not just current state. This enables better
customer understanding and predictive capabilities.

## Getting Started

The fastest way to see value from dbt-nexus:

1. **Start with 2-3 key data sources** (email, payments, and your core product)
2. **Build a simple timeline view** for your support team
3. **Add sources incrementally** as you see value
4. **Integrate with your existing tools** rather than replacing them

## Results

dbt-nexus has become the central piece of our company's operating system,
enabling us to:

- Provide faster, more informed customer support
- Close more sales with complete customer context
- Reduce churn through proactive outreach
- Build better products using comprehensive usage data

Want help building your own dbt-nexus instance?
[Contact us](mailto:hello@slideruleanalytics.com) for consultation and
implementation support.

## Related Resources

- [Package Architecture](architecture.md) - Technical deep dive
- [Identity Resolution Logic](identity-resolution.md) - How entity matching
  works
- [Getting Started Guide](../getting-started/) - Implementation steps
- [Blog](/blog) - More
  real-world examples
