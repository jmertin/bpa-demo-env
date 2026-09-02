<?php
/**
 * URL routing helpers.
 *
 * Centralizes every internal link, form action, and redirect so the whole
 * app can switch between "mp" (metric-path clean URLs, e.g. /shop -- the
 * default) and "plain" (index.php?page=... query-variable, the original
 * front-controller layout) routing via the single APP_TYPE environment
 * variable, with no per-call-site branching anywhere else in the app.
 */

/**
 * Determine whether URL-path-based routing ("mp" mode) is active.
 *
 * @return bool
 *   TRUE for "mp" (or when APP_TYPE is unset -- mp is the default); FALSE
 *   for "plain".
 */
function app_type_is_mp(): bool {
  return (getenv('APP_TYPE') ?: 'mp') !== 'plain';
}

/**
 * Build a URL to an application page, honouring APP_TYPE.
 *
 * @param string $page
 *   Page slug (e.g. 'shop', 'basket').
 * @param array $params
 *   Additional query-string parameters, keyed by name. Values that are
 *   '', null, or false are dropped, matching this app's existing
 *   array_filter() convention for optional query params.
 *
 * @return string
 *   e.g. '/shop?q=foo' in mp mode, '/index.php?page=shop&q=foo' in plain
 *   mode.
 */
function page_url(string $page, array $params = []): string {
  $params = array_filter($params, fn($v) => $v !== '' && $v !== null && $v !== false);
  if (app_type_is_mp()) {
    $path = '/' . $page;
    return $params ? $path . '?' . http_build_query($params) : $path;
  }
  return '/index.php?' . http_build_query(['page' => $page] + $params);
}

/**
 * Build the form 'action' attribute for a page's own GET/POST forms.
 *
 * @param string $page
 *   Page slug the form should submit to.
 *
 * @return string
 *   e.g. '/shop' in mp mode, '/index.php' in plain mode.
 */
function page_form_action(string $page): string {
  return app_type_is_mp() ? '/' . $page : '/index.php';
}

/**
 * Render a hidden 'page' input for a GET form, if needed.
 *
 * GET form submission discards action="...?page=X"'s own query string per
 * the HTML forms spec, so a plain-mode GET form must carry the page slug
 * as a hidden input instead. Not needed in mp mode, since the page slug
 * is already baked into the form's action path.
 *
 * @param string $page
 *   Page slug the form should submit to.
 *
 * @return string
 *   The hidden <input> tag, or '' in mp mode.
 */
function page_hidden_input(string $page): string {
  if (app_type_is_mp()) {
    return '';
  }
  return '<input type="hidden" name="page" value="' . htmlspecialchars($page) . '">';
}
