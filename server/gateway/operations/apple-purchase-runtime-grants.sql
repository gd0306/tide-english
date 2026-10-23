GRANT SELECT,INSERT ON apple_purchase_notifications TO tideenglish_runtime;
GRANT UPDATE(provider_revision,provider_evidence_hash) ON ai_value_purchase_transactions TO tideenglish_runtime;
REVOKE ALL ON apple_notification_cursors FROM tideenglish_runtime;
GRANT SELECT,INSERT,UPDATE ON apple_notification_cursors TO tideenglish_runtime;
