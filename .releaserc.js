// .releaserc.js
// Commits from external contributors (anyone not 'hamidi-dev') get a
// "thanks @author" suffix automatically in the release notes.
const MAINTAINER_NAMES = ['mohamed hamidi', 'hamidi-dev']

module.exports = {
  branches: ['main'],
  plugins: [
    [
      '@semantic-release/commit-analyzer',
      {
        preset: 'conventionalcommits',
        releaseRules: [
          { type: 'feat', release: 'minor' },
          { type: 'fix', release: 'patch' },
          { type: 'perf', release: 'patch' },
          { type: 'revert', release: 'patch' },
          { type: 'docs', release: false },
          { type: 'chore', release: false },
          { type: 'refactor', release: 'patch' },
          { type: 'test', release: false },
          { breaking: true, release: 'major' },
        ],
      },
    ],
    [
      '@semantic-release/release-notes-generator',
      {
        preset: 'conventionalcommits',
        presetConfig: {
          types: [
            { type: 'feat', section: 'Features' },
            { type: 'fix', section: 'Bug Fixes' },
            { type: 'perf', section: 'Performance' },
            { type: 'refactor', section: 'Code Refactoring' },
            { type: 'docs', section: 'Documentation', hidden: false },
            { type: 'chore', hidden: true },
            { type: 'test', hidden: true },
          ],
        },
        writerOpts: {
          transform: (commit, context) => {
            if (!commit.type) return commit

            const login = commit.authorName || ''
            // Append contributor credit for anyone who isn't the maintainer
            if (login && !MAINTAINER_NAMES.includes(login.toLowerCase())) {
              commit.subject = `${commit.subject} — thanks @${login}`
            }

            return commit
          },
        },
      },
    ],
    [
      '@semantic-release/changelog',
      {
        changelogFile: 'CHANGELOG.md',
        changelogTitle: '# Changelog\n\nAll notable changes to this project will be documented in this file.',
      },
    ],
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md'],
        message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
      },
    ],
    '@semantic-release/github',
  ],
}
