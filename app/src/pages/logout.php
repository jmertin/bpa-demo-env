<?php
auth_logout();
header('Location: ' . page_url('shop'));
exit;
