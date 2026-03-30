" set rtp+=/home/linuxbrew/.linuxbrew/opt/fzf

" >>>>> cursor style <https://stackoverflow.com/a/42118416/18012824> >>>>>
let &t_SI = "\e[6 q"
let &t_EI = "\e[2 q"
" reset the cursor on start (for older versions of vim, usually not required)
augroup myCmds
au!
autocmd VimEnter * silent !echo -ne "\e[2 q"
augroup END
" <<<<< cursor style <<<<<

syntax on
set number
set wrap
set showcmd
set wildmenu
set timeout
set timeoutlen=300
set ttimeout
set ttimeoutlen=10

" set hlsearch
" exec "nohlsearch"
" set incsearch
" set ignorecase
" set smartcase

" set shiftwidth=2
" set softtabstop=2
" set list
" set listchars=tab:▸\ ,trail:▫
" set scrolloff=5
" set tw=0
" set indentexpr=
" set backspace=indent,eol,start
" set foldmethod=indent
" set foldlevel=99
" set laststatus=2

noremap K 5k
noremap J 5j

set nocompatible

" Based on <https://github.com/cposture/my-vim>

"############################################### begin vim-plug ################################
call plug#begin()
"CurtineIncSw.vim 插件，用于头文件源文件来回切换
Plug 'ericcurtin/CurtineIncSw.vim'
"Molokai 主题
Plug 'tomasr/molokai'
"solarized 主题
Plug '~/vim-plugin/altercation/vim-colors-solarized'
"自动补全括号插件
Plug 'jiangmiao/auto-pairs'
call plug#end()
"############################################### end vim-plug ##################################





"############################################### begin common-conf #############################
"=========================================
" 键盘配置
"=========================================
"设置快捷键的前缀
let mapleader = ","
"可以在buffer的任何地方使用鼠标（类似office中在工作区双击鼠标定位）
set mouse=a
"mac下支持 yy 等将内容复制到操作系统粘贴版
set clipboard=unnamed
" CTRL + LEFT 打开 buffer 文件列表下个文件
nnoremap <C-LEFT> :bn<CR>
" CTRL + RIGHT 打开 buffer 文件列表上个文件
nnoremap <C-RIGHT> :bp<CR>
" CTRL + N 打开下一个 tab
nnoremap <C-N> :tabn<CR>
" CTRL + P 打开上一个 tab
nnoremap <C-P> :tabp<CR>

"=========================================
" 语言配置
"=========================================
"编码
set termencoding=utf-8
set encoding=utf8
set fileencodings=utf8,ucs-bom,gbk,cp936,gb2312,gb18030
" python tab 长度为 4
autocmd Filetype python setlocal expandtab tabstop=4 shiftwidth=4 softtabstop=4
" 开启文件类型检查，这将触发FileType事件，该事件可用于设置语法突出显示，设置选项等
filetype on
" 开启文件类型插件，会在'runtimepath'中加载文件“ftplugin.vim”
filetype plugin on
" 开启文件类型缩进，会在'runtimepath'中加载文件“indent.vim”
filetype indent on
"将输入的TAB自动展开成空格。开启后要输入TAB，需要Ctrl-V<TAB>
set expandtab
"使用每层缩进的空格数
set shiftwidth=4
"编辑时一个TAB字符占多少个空格的位置
set tabstop=4
"方便在开启了et后使用退格（backspace）键，每次退格将删除X个空格
set softtabstop=4
" 使回格键（backspace）正常处理indent(缩进位置), eol(行结束符), start(段首), 很奇怪 Vim 默认竟然不允许在这些地方使用 backspace
set backspace=indent,eol,start
"开启时，在行首按TAB将加入 shiftwidth 个空格，否则加入 tabstop 个空格
set smarttab
"设置光标超过 130 列的时候折行
"set tw=130
"不在单词中间断行，如果一行文字非常长，无法在一行内显示完的话，它会在单词与单词间的空白处断开
"尽量不会把一个单词分成两截放在两个不同的行里
set lbr
"打开断行模块对亚洲语言支持
"m 表示允许在两个汉字之间断行，即使汉字之间没有出现空格
"B 表示将两行合并为一行的时候，汉字与汉字之间不要补空格
set fo+=mB
"显示括号配对情况。打开这个选项后，当输入后括号(包括小括号、中括号、大括号) 的时候，光标会跳回前括号片刻，然后跳回来，以此显示括号的配对情况
"带有如下符号的单词不要被换行分割
set iskeyword+=$,@,%,#,-,_
set sm
"缩进方式，每一行都和前一行有相同的缩进量，当遇到右花括号（}）等，则取消缩进形式
"set smartindent
"缩进方式，用C语言的缩进格式来处理程序的缩进结构
set cindent
"设置当文件被改动时自动载入
set autoread
"当你编辑下一个文件的时候，目前正在编辑的文件如果改动，将会自动保存
set autowrite
"tags 配置
set tags=tags;
"输出时只有文件名，不带./ ../等目录前缀(默认了执行％在当前的目录下)
set autochdir 
"禁止生成临时文件
set noundofile
set nobackup
set noswapfile
"搜索忽略大小写
set ignorecase
augroup file_type
    autocmd!
    "为特定后缀的文件设置文件类型
    autocmd BufRead,BufNewFile *.{md,mdown,mkd,mkdn,markdown,mdwn}   set filetype=mkd
    autocmd BufRead,BufNewFile *.{go}   set filetype=go
    autocmd BufRead,BufNewFile *.{js}   set filetype=javascript
    autocmd BufRead,BufNewFile *.{htm}   set filetype=html
augroup END

"=========================================
" 显示配置
"=========================================
if has("gui_running")
    au GUIEnter * simalt ~x " 窗口启动时自动最大化
    set guioptions-=m " 隐藏菜单栏
    set guioptions-=T " 隐藏工具栏
    set guioptions-=L " 隐藏左侧滚动条
    set guioptions-=r " 隐藏右侧滚动条
    set guioptions-=b " 隐藏底部滚动条
    "set showtabline=0 " 隐藏Tab栏
endif
"打开 vim 语法高亮
syntax on
"在命令模式下使用 Tab 自动补全的时候，将补全内容使用一个漂亮的单行菜单形式显示出来
set wildmenu
"指定在选择文本时，光标所在位置也属于被选中的范围。如果指定 selection=exclusive 的话，可能会出现某些文本无法被选中的情况
set selection=inclusive
"选择字符，使用鼠标时或 shift+特殊键时进入选择模式
set selectmode=mouse,key
"当右键单击窗口的时候，弹出快捷菜单, GUI
set mousemodel=popup
"256位色
set t_Co=256
"高亮光标所在行
set cul
"高亮光标所在列
" set cuc
"显示行号
set number
"显式相对行号
" set rnu
"历史记录数
set history=10000
"在屏幕右下角显示未完成的指令输入，有时候我们输入的命令不是立即生效的，它会稍作等待，等候你是否输入某种组合指令 
set showcmd
"光标移动到buffer的顶部和底部时保持3行距离
set scrolloff=3
"光标移动的距离
set scroll=1
"高亮显示匹配的括号
set showmatch
"匹配括号高亮的时间（单位是十分之一秒）
set matchtime=1
"显示状态栏
set laststatus=2
"突出显示当前行
set cursorline
"设置魔术
set magic
"打开搜索高亮模式，若搜索找到匹配项就高亮显示所有匹配项
set hlsearch
"打开增量搜索模式，Vim 会即时匹配你当前输入的内容，这样会给你更好的搜索反馈
set incsearch
"语言设置
set langmenu=zh_CN.UTF-8
"如果有，就使用vim 中文帮助文档
set helplang=cn
"设置命令行的高度
set cmdheight=1
"menu:匹配多于一个使用弹框显示补全，longest:不懂
set completeopt=longest,menu
"在处理未保存或只读文件的时候，弹出确认
set confirm
"使用 :commands 命令模式时总是报告修改的行数
set report=0
" 在被分割的窗口间显示空白，便于阅读
set fillchars=vert:\ ,stl:\ ,stlnc:\ 
augroup vimrcEx
    "当打开一个文件，跳到上次光标所在位置
    autocmd BufReadPost *
                \ if line("'\"") > 0 && line("'\"") <= line("$") |
                \   exe "normal g`\"" |
                \ endif
    " quickfix 模式
    autocmd FileType c,cpp noremap <buffer> <leader><space> :w<cr>:make<cr>
augroup END

"=========================================
" vim omnicompletion 配置
"=========================================
"OmniCppComplete 是根据 Ctags 生成的索引文件进行补全
"开启各种语言的补全
autocmd FileType java setlocal omnifunc=javacomplete#Complete
autocmd FileType cs setlocal omnifunc=OmniSharp#Complete
autocmd FileType python set omnifunc=python3complete#Complete
autocmd FileType JavaScript set omnifunc=javascriptcomplete#CompleteJS
autocmd FileType html set omnifunc=htmlcomplete#CompleteTags
autocmd FileType css set omnifunc=csscomplete#CompleteCSS
autocmd FileType xml set omnifunc=xmlcomplete#CompleteTags
autocmd FileType php set omnifunc=phpcomplete#CompletePHP
autocmd FileType c set omnifunc=ccomplete#Complete
autocmd FileType javascript set omnifunc=javascriptcomplete#CompleteJS
"############################################### end common-conf ###############################




"############################################### begin 所有插件配置 #############################
"=========================================
" molokai 插件配置
"=========================================
"设置背景主题
let g:rehash256=1
let g:molokai_original = 1
color molokai

"=========================================
" vim-colors-solarized 插件配置
"=========================================
"syntax enable
"set background=dark
"colorscheme solarized

"############################################### enc 所有插件配置 ###############################
