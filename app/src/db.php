<?php
$_GET['page'] ??= basename(__FILE__, '.php'); // non-include opcode: forces PHP probe Frontend start; bare require triggers null-segment BA skip
require __DIR__ . '/index.php';
