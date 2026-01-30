# Changelog

All notable changes to this project will be documented in this file.

## 1.0.0 (2026-01-30)

### ⚠ BREAKING CHANGES

* complete refactor for easier maintainability
* adds new view with calculation of days

### Features

* add popup_mode for tmux session integration ([b21981e](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/b21981e0680229c2bfb18deed2e74d0d2001be88))
* add set_state keymap with menu for direct state setting ([d29c219](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/d29c21961b9c3e53eab6f01fcec2df32815ca2f3))
* add time display support for scheduled/deadline timestamps ([6b59f74](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/6b59f74ae09d2d79f26a2371bd9da82f525bc768)), closes [#7](https://github.com/hamidi-dev/org-super-agenda.nvim/issues/7)
* adds customizable sorting for groups ([f332a16](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/f332a16ae84a4cc700c47fe2c1bd48c79d3e694d))
* adds help menu ([e9d2612](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/e9d26122f9dc887e131a14f2666b7c1f81aa671f))
* adds new view with calculation of days ([8c02602](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/8c02602baa87eec43966c13a003a0e2775f41811))
* advanced filtering using queries ([8faabb8](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/8faabb89b2d076c80f1218c75fa2870dbc1b172b))
* change deadline and schedule using datepicker ([84666d5](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/84666d54b83883ddbb41428f63bd87740bf22fa3))
* change priorities ([27ed667](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/27ed6670d7e2fd21dfc5e3fd69bc76963ede650b))
* complete refactor for easier maintainability ([75af98e](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/75af98ed7250b79c90757bb1053768bccc78f702))
* config for short date labels ([1009151](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/100915176fc2c13809035f658b5df64acc1e11cd))
* config options to exclude files / folder to speed up initial loading ([ee7c581](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/ee7c58104817adbc232c9c1a909a2633fcc80eef))
* config options to hide duplicates by default + keymap to toggle ([f580462](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/f580462cc5bbe765ea16b36f1390cad76e908186))
* config options to hide duplicates by default + keymap to toggle ([1575d57](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/1575d57da7e6f63a572093a3e718e3b002b6c09c))
* cycle TODO states ([db55e53](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/db55e5399d6872a023512aa469262f657d249b77))
* enable cursorline ([3410596](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/3410596b523f20319ea38cf19050a88b8a3e24f5))
* has_more indicator as ... ([4fe4ac3](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/4fe4ac32eab57a6ac07abcb712e6f1dd5efda7a4))
* hide headline under cursor + reset hidden ([e94b831](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/e94b831aa86a1a1b485eef56be125b23dbbb7f52))
* include scheduled items with no TODO state + Cycling states is undoable ([7c99a21](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/7c99a215bc06426a18238748d3fa1cbfddf6738f))
* live exact filtering + live fuzzy filtering ([9cea943](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/9cea943d53cb44d4bcfa6261bf44beb65280eafb))
* preview headline with K ([1721f0c](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/1721f0c3d6b235c059ad37bf737c690936618724))
* quick filter keymaps for the different TODO states ([34dc93e](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/34dc93e02d62f1fc968a1a8277a01e6b13ad4959))
* refile via telescope ([8b45c41](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/8b45c416a2aa755a9ab6dd73561237d334006abe))
* refresh / reload agenda ([1101700](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/1101700c6439ad116b26b59d3460ac1da0316153))
* subheadings inherit tags from parent headings ([2ed905e](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/2ed905e666788a784bc3e275d11dbc20683b74af))
* support filtering for active/inactive dates ([276d892](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/276d89224a79a052f11f67a4524c825072092d5a))
* toggle catch-all group ([5ac67f2](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/5ac67f283544359ab67ed7e9016f882643693503))
* truncate long headings ([364e9e1](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/364e9e14d79ad53018cfa44943e9d0211435a2ce))
* undo schedule, deadline, prio ([f0cbb3f](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/f0cbb3f393a68ee83d791ee359fcf4e0f0e7364c))

### Bug Fixes

* add filter_reset (oa) to help menu ([b881b05](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/b881b0571d06fa55ca34989d9cdb07d6df9e9acd))
* add workflow permissions for semantic-release ([d6918f2](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/d6918f2b0a51b1c8cd2da8e7485b3d5d03bc638b))
* deprecated tbl_islist ([9c95700](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/9c957002f00ce729d40265cad058110d2e543d1d))
* drop headlines without TODO state ([75e137f](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/75e137f13b9a4b162b97a9b45652ac463945d8d8))
* eliminate "flicker" when performing actions ([a53d50c](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/a53d50c7ab79370335d5073207b2f1318c8db196))
* org buffers close on opening OrgSuperAgenda ([124bd43](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/124bd431c9441b283e734da18f35eb4a7293f803))
* preserve fullscreen state on agenda refresh ([d75c954](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/d75c954f78746c44e4a3c12c0690d5acfbdcf3f7))
* reset filters ([21239cc](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/21239ccfb95ba64014311fa3eeb94dd927f1d969))

### Code Refactoring

* view.lua ([521785b](https://github.com/hamidi-dev/org-super-agenda.nvim/commit/521785b3c23ec59939fcd4a3240864d69b81febf))
