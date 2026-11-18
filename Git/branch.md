## git branch
### change branch name
正位于要改名的本地分支，直接执行：

`git branch -m 新分支名`

如果要改的是另一个本地分支，不用切过去： 

`git branch -m 旧分支名 新分支名`

> 改完用 git branch 确认。改名不会改变已有提交，也不会丢掉未提交的改动
