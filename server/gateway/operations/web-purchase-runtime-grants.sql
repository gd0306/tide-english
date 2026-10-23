-- Apply after migration034. No general sign-in or financial privileges are added.
REVOKE ALL ON web_purchase_challenges,web_purchase_sessions,web_purchase_limits FROM tideenglish_runtime;
GRANT SELECT,INSERT,DELETE ON web_purchase_challenges,web_purchase_sessions,web_purchase_limits TO tideenglish_runtime;
GRANT UPDATE(used_at,attempts,encrypted_delivery,delivery_state,delivery_attempts,next_delivery_at,
  delivery_lease_until,provider_message_id) ON web_purchase_challenges TO tideenglish_runtime;
GRANT UPDATE(revoked_at) ON web_purchase_sessions TO tideenglish_runtime;
GRANT UPDATE(hits) ON web_purchase_limits TO tideenglish_runtime;
