{ pkgs, ... }:
{
  environment.variables = {
    EDITOR = "vim";
  };

  environment.systemPackages = with pkgs; [
    powerline-fonts
    (vim_configurable.customize
    {
      name = "vim";
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins;
      {
        start = [
          airline
          vim-airline-themes
          vim-nix
          vim-lastplace
          nerdtree
        ];
        opt = [];
      };

      vimrcConfig.customRC = ''
        set encoding=utf-8
        autocmd FileType nix :packadd vim-nix
        set title
        set backspace=indent,eol,start
        set colorcolumn=101
        set tabstop=2
        set shiftwidth=2
        set expandtab
        set background=dark
        colorscheme unokai
        set laststatus=2
        set showtabline=2
        set smartindent
        syntax enable
        set number
        set spell spelllang=en_au
        hi clear SpellBad
        hi SpellBad cterm=underline
        hi SpellBad ctermbg=NONE
        match ErrorMsg '\s\+$'

        " Toggle NERDTree.
        map <C-o> :NERDTreeToggle<CR>


        if !exists('g:airline_symbols')
          let g:airline_symbols = {}
        endif

        let g:airline_theme='dark'
        let g:airline_powerline_fonts = 1
        let g:airline_section_b = '%{getcwd()}'
        let g:airline#extensions#tabline#enabled = 1
        let g:airline#extensions#tabline#show_close_button = 0
        let g:airline#extensions#tabline#tabs_label = ''''''
        let g:airline#extensions#tabline#buffers_label = ''''''
        let g:airline#extensions#tabline#fnamemod = ':t'
        let g:airline#extensions#tabline#show_tab_count = 0
        let g:airline#extensions#tabline#show_buffers = 0
        let g:airline#extensions#tabline#tab_min_count = 2
        let g:airline#extensions#tabline#show_splits = 0
        let g:airline#extensions#tabline#show_tab_nr = 0
        let g:airline#extensions#tabline#show_tab_type = 0

        let g:airline_section_z = airline#section#create(['windowswap', '%3p%% ', 'R:%l ', 'C:%v'])

        let g:airline_symbols.crypt = '🔒'
        let g:airline_symbols.linenr = 'R: '
        let g:airline_symbols.maxlinenr = ' '
        let g:airline_symbols.branch = '⎇'
        let g:airline_symbols.paste = 'ρ'
        let g:airline_symbols.spell = 'Ꞩ'
        let g:airline_symbols.notexists = 'Ɇ'
        let g:airline_symbols.notexists = '∄'
        let g:airline_symbols.whitespace = ' '
        let g:airline_left_sep = ''
        let g:airline_left_alt_sep = ''
        let g:airline_right_sep = ''
        let g:airline_right_alt_sep = ''
        let g:airline_symbols.branch = ''
        let g:airline_symbols.colnr = ' '
        let g:airline_symbols.readonly = ''
        let g:airline_symbols.dirty='⚡'
      '';
    })
  ];
}

