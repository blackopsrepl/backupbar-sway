const versionFile = {
  filename: 'lib/backupbar.rb',
  updater: {
    readVersion(contents) {
      const match = contents.match(/VERSION = "([^"]+)"/);
      return match ? match[1] : null;
    },
    writeVersion(contents, version) {
      return contents.replace(/(VERSION = ")[^"]+("?)/, `$1${version}$2`);
    },
  },
};

module.exports = {
  packageFiles: [versionFile, 'package.json', 'package-lock.json'],
  bumpFiles: [versionFile, 'package.json', 'package-lock.json'],
  tagPrefix: 'v',
  releaseCommitMessageFormat: 'chore(release): {{currentTag}}',
  host: 'http://vigilance:3002',
  owner: 'blackopsrepl',
  repository: 'backupbar-sway',
  commitUrlFormat: 'http://vigilance:3002/blackopsrepl/backupbar-sway/commit/{{hash}}',
  compareUrlFormat: 'http://vigilance:3002/blackopsrepl/backupbar-sway/compare/{{previousTag}}...{{currentTag}}',
  issueUrlFormat: 'http://vigilance:3002/blackopsrepl/backupbar-sway/issues/{{id}}',
};
