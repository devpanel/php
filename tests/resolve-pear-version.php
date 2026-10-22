<?php

require __DIR__ . '/../base/resolve-pear-version.php';

$releases = simplexml_load_string('<a xmlns="http://pear.php.net/dtd/rest.allreleases">
    <r><v>1.10.18</v><s>stable</s></r>
    <r><v>1.11.0</v><s>stable</s></r>
    <r><v>1.12.0</v><s>beta</s></r>
    <r><v>1.10.20</v><s>stable</s></r>
    <r><v>../../invalid</v><s>stable</s></r>
</a>');
$requirements = [
    '1.10.18' => '<min>5.4.0</min>',
    '1.10.20' => '<min>7.4.0</min><max>8.4.99</max><exclude>8.0.30</exclude>',
    '1.11.0' => '<min>8.1.0</min>',
];
$metadata = function ($url) use ($requirements) {
    $version = basename($url, '.xml');
    $version = substr($version, strlen('package.'));
    if (!isset($requirements[$version])) {
        throw new RuntimeException("Unexpected metadata request: $url");
    }
    return simplexml_load_string(
        '<package xmlns="http://pear.php.net/dtd/package-2.0">'
        . '<dependencies><required><php>' . $requirements[$version]
        . '</php></required></dependencies></package>'
    );
};

foreach (['7.4.33' => '1.10.20', '8.0.30' => '1.10.18', '8.5.12' => '1.11.0'] as $php => $expected) {
    $actual = compatiblePearVersion($releases, $php, '1.10.18', $metadata);
    if ($actual !== $expected) {
        throw new RuntimeException("PHP $php: expected $expected, got $actual");
    }
}

$olderReleases = simplexml_load_string('<a>
    <r><v>1.10.20</v><s>stable</s></r>
    <r><v>1.10.18</v><s>stable</s></r>
</a>');
if (compatiblePearVersion($olderReleases, '8.5.12', '1.10.18', $metadata) !== '1.10.18') {
    throw new RuntimeException('PHP maximum was not respected');
}

foreach ([
    function () use ($releases, $metadata) {
        compatiblePearVersion($releases, '5.3.0', '1.10.18', $metadata);
    },
    function () use ($releases, $metadata) {
        compatiblePearVersion($releases, '7.4.33', '1.11.0', $metadata);
    },
    function () use ($releases) {
        compatiblePearVersion($releases, '7.4.33', '1.10.18', function () {
            return simplexml_load_string('<package/>');
        });
    },
    function () use ($metadata) {
        compatiblePearVersion(simplexml_load_string('<a/>'), '7.4.33', '1.10.18', $metadata);
    },
] as $failure) {
    try {
        $failure();
    } catch (RuntimeException $expected) {
        continue;
    }
    throw new RuntimeException('Expected resolution to fail');
}

echo "PEAR compatibility selection checks passed\n";
