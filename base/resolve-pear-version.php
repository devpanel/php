<?php

function pearMetadata(string $url): SimpleXMLElement
{
    $output = [];
    exec(
        'curl -fsSL --compressed --retry 5 --retry-all-errors --connect-timeout 10 '
        . escapeshellarg($url),
        $output,
        $status
    );
    if ($status !== 0) {
        throw new RuntimeException("Failed to fetch PEAR metadata: $url");
    }
    $xml = simplexml_load_string(implode("\n", $output), 'SimpleXMLElement', LIBXML_NONET);
    if ($xml === false) {
        throw new RuntimeException("Invalid PEAR metadata: $url");
    }
    return $xml;
}

function compatiblePearVersion(
    SimpleXMLElement $releases,
    string $phpVersion,
    string $minimum,
    callable $metadata
): string {
    $versions = [];
    foreach ($releases->r as $release) {
        $version = (string) $release->v;
        if ((string) $release->s === 'stable'
            && preg_match('/^[0-9]+(?:\.[0-9]+)+$/D', $version)
            && version_compare($version, $minimum, '>=')
        ) {
            $versions[] = $version;
        }
    }
    usort($versions, function ($a, $b) {
        return version_compare($b, $a);
    });
    foreach ($versions as $version) {
        $package = $metadata("https://pear.php.net/rest/r/pear/package.$version.xml");
        if (!isset($package->dependencies->required->php->min)) {
            throw new RuntimeException("Missing PHP requirements for PEAR $version");
        }
        $php = $package->dependencies->required->php;
        if ((string) $php->min === '') {
            throw new RuntimeException("Empty PHP minimum for PEAR $version");
        }
        if (version_compare($phpVersion, (string) $php->min, '<')
            || ((string) $php->max !== '' && version_compare($phpVersion, (string) $php->max, '>'))
        ) {
            continue;
        }
        foreach ($php->exclude as $excluded) {
            if (version_compare($phpVersion, (string) $excluded, '==')) {
                continue 2;
            }
        }
        return $version;
    }
    throw new RuntimeException("No stable PEAR release >= $minimum supports PHP $phpVersion");
}

if (realpath($_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    try {
        echo compatiblePearVersion(
            pearMetadata('https://pear.php.net/rest/r/pear/allreleases.xml'),
            PHP_VERSION,
            $argv[1],
            'pearMetadata'
        ), "\n";
    } catch (Throwable $error) {
        fwrite(STDERR, $error->getMessage() . "\n");
        exit(1);
    }
}
