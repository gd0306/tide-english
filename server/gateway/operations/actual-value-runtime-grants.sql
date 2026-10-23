-- Apply after migrations017/018 and the existing billing/voice/helper grants.
-- Runtime may settle funds, but only a privileged operator can approve historical cash provenance.
REVOKE ALL ON deployment_environment FROM tideenglish_runtime;
GRANT SELECT ON deployment_environment TO tideenglish_runtime;
REVOKE ALL ON FUNCTION protect_deployment_environment() FROM tideenglish_runtime;
GRANT EXECUTE ON FUNCTION lock_ai_pricing_policy() TO tideenglish_runtime;
REVOKE INSERT,UPDATE,DELETE ON ai_pricing_policy,ai_pricing_audit FROM tideenglish_runtime;
GRANT SELECT ON wallets,ledger,reservations TO tideenglish_runtime;
GRANT SELECT ON hosted_sessions,hosted_helper_sessions TO tideenglish_runtime;
REVOKE UPDATE ON wallets FROM tideenglish_runtime;
GRANT UPDATE(balance_nano,reserved_nano,sandbox_balance_nano) ON wallets TO tideenglish_runtime;
REVOKE UPDATE(cash_provenance_verified) ON wallets FROM tideenglish_runtime;
GRANT INSERT ON ledger,reservations TO tideenglish_runtime;
-- Column revocation cannot override a legacy table-wide UPDATE grant.
-- Reset both grant levels before allowing only lifecycle and settlement writes.
REVOKE UPDATE ON reservations,hosted_sessions FROM tideenglish_runtime;
DO $runtime_grants$
DECLARE target regclass; columns text;
BEGIN
  FOR target IN SELECT unnest(ARRAY['reservations'::regclass,'hosted_sessions'::regclass]) LOOP
    SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO columns
      FROM pg_attribute WHERE attrelid=target AND attnum>0 AND NOT attisdropped;
    EXECUTE format('REVOKE UPDATE (%s) ON %s FROM tideenglish_runtime',columns,target);
  END LOOP;
END;
$runtime_grants$;
GRANT UPDATE(state,actual_nano) ON reservations TO tideenglish_runtime;
GRANT UPDATE(provider_session_id,state,deadline,close_requested_at,observed_ms,provider_cost_nano,
  charged_nano,funding_exposure_nano,close_reason,charged_ms,provider_attempted_at,
  provider_rejection_status,provider_rejection_request_id) ON hosted_sessions TO tideenglish_runtime;
REVOKE UPDATE,DELETE ON ledger FROM tideenglish_runtime;

REVOKE ALL ON ai_value_purchase_quotes,ai_value_purchase_transactions,hosted_cash_reconciliation FROM tideenglish_runtime;
GRANT SELECT,INSERT ON ai_value_purchase_quotes,ai_value_purchase_transactions,hosted_cash_reconciliation TO tideenglish_runtime;
GRANT UPDATE(state,granted_nano,refunded_minor,reversed_nano,updated_at) ON ai_value_purchase_transactions TO tideenglish_runtime;
GRANT UPDATE(cash_pool_nano) ON hosted_helper_sessions TO tideenglish_runtime;
REVOKE UPDATE(funding_mode,limit_ms) ON hosted_sessions FROM tideenglish_runtime;
REVOKE UPDATE(cash_funded) ON hosted_helper_sessions FROM tideenglish_runtime;
REVOKE UPDATE(cash_reservation_id) ON hosted_helper_requests FROM tideenglish_runtime;
REVOKE UPDATE(funding_environment) ON reservations,hosted_sessions,hosted_helper_sessions FROM tideenglish_runtime;
REVOKE ALL ON FUNCTION preserve_apple_funding_scope() FROM tideenglish_runtime;
REVOKE ALL ON FUNCTION verify_ai_value_quote_link(),protect_ai_value_purchase_transaction(),
  preserve_hosted_paid_contract(),preserve_hosted_cash_binding(),check_hosted_cash_binding() FROM tideenglish_runtime;
