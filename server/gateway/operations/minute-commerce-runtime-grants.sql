REVOKE ALL ON minute_play_void_cursors FROM tideenglish_runtime;
GRANT SELECT,INSERT ON minute_play_void_cursors TO tideenglish_runtime;
GRANT UPDATE(completed_through_ms,window_start_ms,window_end_ms,page_token,next_poll_after,updated_at)
  ON minute_play_void_cursors TO tideenglish_runtime;
