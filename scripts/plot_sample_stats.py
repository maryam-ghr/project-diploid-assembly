#!/usr/bin/env python3

import os as os
import sys as sys
import logging as log
import io as io
import traceback as trb
import argparse as argp
import pickle as pck

import numpy as np
import matplotlib as mpl
mpl.use('Agg')
import matplotlib.pyplot as plt
log.getLogger('matplotlib.font_manager').disabled = True


def parse_command_line():
    """
    :return:
    """
    parser = argp.ArgumentParser(prog="plot_sample_stats.py", description=__doc__)
    parser.add_argument(
        "--debug",
        "-d",
        action="store_true",
        default=False,
        dest="debug",
        help="Print status and error messages to STDOUT. Otherwise, only"
        " errors/warnings will be reported to STDERR.",
    )
    parser.add_argument(
        "--pck-input",
        "-pi",
        type=str,
        required=True,
        dest="input",
        help="Single pickled statistics file as generated by collect_read_stats.py",
    )
    parser.add_argument(
        "--sample-name",
        "-sn",
        type=str,
        dest="sample_name",
        help="Name of sample to show in plot - if omitted, use filename w/o extension"
    )
    parser.add_argument(
        "--genome-length",
        "-gl",
        type=str,
        default='3G',
        dest="genome_length",
        help="Specify genome length to compute the (approx.) x-fold read coverage. "
             "Suffix G, M, or K is recognized. Can also be a FASTA index file "
             "(.fai), all values in the second column will be summed up. Note "
             "that if the value 'genome_size' is part of the the pickle dump "
             "loaded, this value will take precedence over the '--genome-length' "
             "parameter. Default: 3G"
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        required=True,
        help="Path to output file - only .pdf or .png is recognized as output format"
    )

    rldist_params = parser.add_argument_group("Customize read length distribution plot")
    rldist_params.add_argument(
        "--lowest-bin",
        "-lb",
        type=int,
        default=5000,
        dest="lowest_bin",
        help="Specify upper boundary of lowest bin. "
             "All values smaller than this are subsumed "
             "in this first bin. Default: 5000"
    )
    rldist_params.add_argument(
        "--highest-bin",
        "-hb",
        type=int,
        default=100000,
        dest="highest_bin",
        help="Specify lower boundary for highest bin. "
             "All values larger than this are subsumed "
             "in this last bin. Default: 100000"
    )
    rldist_params.add_argument(
        "--step-size",
        "-sts",
        type=int,
        default=1000,
        dest="step_size",
        help="Specify a reasonable step size for binning (is sanity checked). "
             "Default: 1000"
    )
    rldist_params.add_argument(
        "--label-every-nth"
        "-ln",
        type=int,
        default=10,
        dest="every_nth",
        help="Label every n-th tick mark on the x-axis in the read "
             "length distribution plot. Default: 5"
    )

    plot_params = parser.add_argument_group("Customize plot appearance")
    plot_params.add_argument(
        "--color",
        "-c",
        type=str,
        default="darkgrey",
        dest="color",
        help="Specify plot color (only matplotlib names supported). Default: darkgrey"
    )
    plot_params.add_argument(
        "--title-size",
        "-ts",
        type=int,
        default=14,
        dest="title_size",
        help="Size of panel titles in points"
    )
    plot_params.add_argument(
        "--axis-label-size",
        "-als",
        type=int,
        default=12,
        dest="label_size",
        help="Size of axis labels in points"
    )
    plot_params.add_argument(
        "--tick-label-size",
        "-tls",
        type=int,
        default=12,
        dest="tick_size",
        help="Size of axis tick labels in points"
    )
    plot_params.add_argument(
        "--text-size",
        "-tx",
        type=int,
        default=16,
        dest="text_size",
        help="Size of text for sample info in points."
    )
    plot_params.add_argument(
        "--figure-size",
        "-fs",
        type=float,
        nargs=2,
        default=(10, 10),
        dest="figsize",
        help="Specify size of whole figure in inches (width x height). "
             "Default: w: 8 in / h: 8 in"
    )
    plot_params.add_argument(
        "--png-resolution",
        "-pr",
        type=int,
        default=300,
        dest="resolution",
        help="Specify resolution of PNG output (dpi). "
             "Default: 300 dpi"
    )

    return parser.parse_args()


def compute_read_statistics(base_counts, read_counts, read_lengths, genome_length):
    """
    :param base_counts:
    :param read_counts:
    :param genome_length:
    :return:
    """

    if genome_length > 1e9:
        simple_length = str(round(genome_length / 1e9, 1)) + ' Gbp'
    elif genome_length > 1e6:
        simple_length = str(round(genome_length / 1e6, 1)) + ' Mbp'
    elif genome_length > 1e3:
        simple_length = str(round(genome_length / 1e3, 1)) + ' kbp'
    else:
        simple_length = str(genome_length) + ' bp'

    sample_infos = []

    total_base_pair = base_counts.sum()
    sample_infos.append('Total bases: {}'.format(total_base_pair))

    total_reads = read_counts.sum()
    sample_infos.append('Total reads: {}'.format(total_reads))

    xfold_cov = round(total_base_pair / genome_length, 2)
    sample_infos.append('Coverage: ~{}x (at {})'.format(xfold_cov, simple_length))

    sample_infos.append('Shortest read: {}'.format(read_lengths.min()))
    sample_infos.append('Longest read: {}'.format(read_lengths.max()))

    percentiles = np.cumsum(read_counts) / total_reads
    pct_values = []
    for pct in [0.25, 0.5, 0.75, 0.95]:
        selector = np.array(percentiles > pct, dtype=np.bool)
        min_len = read_lengths[selector].min()
        pct_values.append(min_len)

    for pct, val in zip([25, 50, 75, 95], pct_values):
        sample_infos.append('{}%-ile length: {}'.format(pct, val))

    return sample_infos


def create_read_length_axis(read_lengths, axis, cargs, genome_length):
    """

    :return:
    """
    # All read lengths observed in the sample
    length_values = np.array(list(read_lengths.keys()), dtype=np.int32)
    length_values.sort()
    # Count number of reads per read length
    read_counts = np.array([read_lengths[l] for l in length_values])
    # Count number of bases per read length
    base_counts = np.array([read_lengths[l] * l for l in length_values])

    base_count_bins = []
    read_count_bins = []

    # define bin boundaries according to user settings
    lo_right_bound = cargs.lowest_bin
    hi_left_bound = cargs.highest_bin
    step = cargs.step_size

    lower = [0, lo_right_bound] + list(range(lo_right_bound + step, hi_left_bound + step, step))
    higher = lower[1:] + [sys.maxsize]

    for l, h in zip(lower, higher):
        # TODO this strikes me as complicated - why did I do this?
        select_low = np.array(length_values >= l, dtype=np.bool)
        select_high = np.array(length_values < h, dtype=np.bool)
        selector = np.logical_and(select_low, select_high)
        base_count_bins.append(base_counts[selector].sum())
        read_count_bins.append(read_counts[selector].sum())

    base_count_bins = np.array(base_count_bins, dtype=np.int64)
    read_count_bins = np.array(read_count_bins, dtype=np.int64)

    x_pos = list(range(len(lower)))
    x_labels = list(map(str, [x // 1000 for x in lower[1:]]))
    x_labels = [x if i % cargs.every_nth == 0 else ' ' for i, x in enumerate(x_labels)]

    axis.bar(x_pos, base_count_bins, width=0.8, align='center', color=cargs.color)
    axis.set_xlabel('Read length < X kbp', fontsize=cargs.label_size)
    axis.set_xticks(x_pos)
    axis.set_xticklabels(x_labels, fontsize=cargs.tick_size)
    axis.set_ylabel('Base count', fontsize=cargs.label_size)

    axis.text(x=0.5, y=0.8, s='Read length max:\n' + str(int(length_values.max())),
              transform=axis.transAxes, fontdict={'fontsize': cargs.text_size, 'color': 'black'})

    tt = axis.set_title('Read length distribution', fontsize=cargs.title_size)
    axis.spines['top'].set_visible(False)
    axis.spines['right'].set_visible(False)

    read_stats = compute_read_statistics(
        base_count_bins,
        read_counts,
        length_values,
        genome_length,
    )

    return axis, tt, read_stats


def create_gc_content_axis(binned_gc, axis, cargs):
    """
    :param binned_gc:
    :param axis:
    :return:
    """
    bins = np.array(list(binned_gc.keys()), dtype=np.int8)
    bins.sort()
    counts = np.array([binned_gc[b] for b in bins], dtype=np.int32)
    axis.ticklabel_format(axis='y', style='sci', scilimits=(0, 5))
    axis.bar(bins, counts, width=1, color=cargs.color)
    axis.set_xlabel('G+C content (% ; binned)', fontsize=cargs.label_size)
    axis.set_ylabel('Read count', fontsize=cargs.label_size)
    axis.tick_params(axis='both', which='major', labelsize=cargs.tick_size)
    tt = axis.set_title('G+C content distribution', fontsize=cargs.title_size)
    axis.spines['top'].set_visible(False)
    axis.spines['right'].set_visible(False)
    return axis, tt


def create_sequenced_bases_axis(base_count, axis, cargs):
    """
    :param base_count:
    :param axis:
    :return:
    """
    count = [base_count[b] for b in 'ACGT']
    xpos = list(range(4))
    axis.bar(xpos, count, width=0.4, align='center', color=cargs.color)
    axis.set_xticks(xpos)
    axis.set_xticklabels(['A', 'C', 'G', 'T'], fontsize=cargs.tick_size)
    axis.set_xlabel('Nucleotide', fontsize=cargs.label_size)
    axis.set_ylabel('# sequenced', fontsize=cargs.label_size)
    tt = axis.set_title('Sequenced bases', fontsize=cargs.title_size)
    axis.spines['top'].set_visible(False)
    axis.spines['right'].set_visible(False)
    return axis, tt


def create_multi_panel_plot(cargs, stats, genome_length, logger):

    fig, axes = plt.subplots(figsize=tuple(cargs.figsize), ncols=2, nrows=2,
                             sharex='none', sharey='none')
    plt.subplots_adjust(hspace=0.3, wspace=0.4)
    fig_tt = fig.suptitle(cargs.sample_name, fontsize=cargs.title_size)

    (sb_ax, gc_ax), (rl_ax, txt_ax) = axes
    sb_ax, sb_ax_tt = create_sequenced_bases_axis(stats['nuc_stats'], sb_ax, cargs)
    gc_ax, gc_ax_tt = create_gc_content_axis(stats['gc_bins'], gc_ax, cargs)
    rl_ax, rl_ax_tt, stats_text = create_read_length_axis(stats['len_stats'], rl_ax, cargs, genome_length)

    if 'summary' in stats:
        logger.debug('Plotting summary info')

        plot_values = [t for t in stats['summary'] if t[0].startswith('cov_geq_')]
        x_values = np.array([int(t[0].split('_')[-1]) for t in plot_values], dtype=np.float16)
        if x_values[1] >= 1000:
            x_values /= 1000
            x_label = 'Read length > X kbp'
        else:
            x_label = 'Read length > x bp'
        x_values = x_values.astype(np.int32)
        txt_ax.set_xlabel(x_label, fontsize=cargs.label_size)

        txt_ax.set_ylabel('x-fold coverage', fontsize=cargs.label_size)
        y_values = np.array([float(t[1]) for t in plot_values])

        txt_ax.plot(x_values, y_values, linestyle='dotted', marker='x', color=cargs.color)
        n50_rlen = [t for t in stats['summary'] if 'read_length_N50' in t[0]]
        n50_rlen = n50_rlen[0][1]
        txt_ax.text(x=0.5, y=0.8, s='Read length N50:\n' + str(n50_rlen), transform=txt_ax.transAxes,
                    fontdict={'fontsize': cargs.text_size, 'color': 'black'})

        txt_ax.spines['top'].set_visible(False)
        txt_ax.spines['right'].set_visible(False)
        txt_ax_tt = txt_ax.set_title('Min. read length for x-fold cov.', fontsize=cargs.title_size)

    else:
        logger.debug('No summary info available, adding textual info...')

        txt_ax.spines['top'].set_visible(False)
        txt_ax.spines['left'].set_visible(False)
        txt_ax.spines['right'].set_visible(False)
        txt_ax.spines['bottom'].set_visible(False)

        logger.debug('Adding sample info text')

        txt_ax.tick_params(axis='both', bottom=False, top=False,
                           left=False, right=False, labeltop=False,
                           labelbottom=False, labelleft=False, labelright=False)

        sample_info = [cargs.sample_name] + stats_text
        sample_info = '\n'.join(sample_info)

        txt_ax.text(x=0., y=0.5, s=sample_info, transform=txt_ax.transAxes,
                    horizontalalignment='left', verticalalignment='center',
                    fontdict={
                        'fontsize': cargs.text_size,
                    }, linespacing=0.11 * cargs.text_size)

    return fig, [fig_tt, sb_ax_tt, gc_ax_tt, rl_ax_tt, txt_ax_tt]


def load_genome_size_from_fai(file_path):
    """
    :param file_path:
    :return:
    """
    genome_length = 0
    with open(file_path, 'r') as fai:
        for line in fai:
            chrom_length = int(line.split()[1])
            genome_length += chrom_length
    return genome_length


def parse_genome_length_string(gen_len_param):
    """
    :param gen_len_param:
    :return:
    """
    factors = {
        'G': 1e9,
        'M': 1e6,
        'K': 1e3
    }
    try:
        genome_length = int(gen_len_param)
    except ValueError:
        numeric, factor = gen_len_param[:-1], gen_len_param[-1]
        genome_length = int(int(numeric) * factors[factor.upper()])
    return genome_length


def derive_genome_length(cargs, stats, logger):
    """
    :param cargs:
    :param stats:
    :param logger:
    :return:
    """
    if 'genome_size' in stats:
        logger.debug('Using genome size from loaded pickle dump')
        genome_length = int(stats['genome_size'])
    elif os.path.isfile(cargs.genome_length):
        logger.debug('Loading genome size from specified file: {}'.format(cargs.genome_length))
        genome_length = load_genome_size_from_fai(cargs.genome_length)
    elif 'genome_size_file' in stats:
        if os.path.isfile(stats['genome_size_file']):
            logger.debug('Loading genome size from previously used file: {}'.format(stats['genome_size_file']))
            genome_length = load_genome_size_from_fai(stats['genome_size_file'])
        else:
            logger.debug('Inferring genome length from string parameter {}'.format(cargs.genome_length))
            genome_length = parse_genome_length_string(cargs.genome_length)
    else:
        logger.debug('Inferring genome length from string parameter {}'.format(cargs.genome_length))
        genome_length = parse_genome_length_string(cargs.genome_length)
    return genome_length


def main(logger, cargs):
    """
    :param logger:
    :param cargs:
    :return:
    """
    logger.debug("Start creating plots for input: {}".format(cargs.input))

    with open(cargs.input, 'rb') as pickled_stats:
        stats = pck.load(pickled_stats)
    logger.debug('Stats successfully loaded')

    genome_length = derive_genome_length(cargs, stats, logger)
    logger.debug('Genome length set to: {} bp'.format(genome_length))

    if not cargs.sample_name:
        setattr(cargs, 'sample_name', os.path.basename(cargs.input).rsplit('.', 1)[0])

    if cargs.step_size > cargs.highest_bin or cargs.step_size < 0:
        raise ValueError('User-specified value for step size is unreasonable: {}'.format(cargs.step_size))
    if cargs.highest_bin % cargs.step_size != 0:
        raise ValueError('Please specify a "highest bin" boundary that is an '
                         'integer multiple of the step size: {} / {}'.format(cargs.step_size, cargs.highest_bin))

    fig, extra_artists = create_multi_panel_plot(cargs, stats, genome_length, logger)

    logger.debug('Figure created')

    outpath = os.path.abspath(os.path.dirname(cargs.output))
    os.makedirs(outpath, exist_ok=True)
    if cargs.output.endswith('.pdf'):
        logger.debug('Figure saved as PDF')
        fig.savefig(cargs.output, bbox_inches='tight', extra_artists=extra_artists)
    elif cargs.output.endswith('.png'):
        logger.debug('Figure saved as PNG')
        fig.savefig(cargs.output, bbox_inches='tight', extra_artists=extra_artists,
                    dpi=cargs.resolution)
    else:
        raise ValueError('Unrecognized image file extension (use pdf or png): {}'.format(cargs.output))

    return


if __name__ == "__main__":
    logger = None
    rc = 0
    try:
        log_msg_format = "%(asctime)s | %(levelname)s | %(message)s"
        cargs = parse_command_line()
        if cargs.debug:
            log.basicConfig(stream=sys.stderr, level=log.DEBUG, format=log_msg_format)
        else:
            log.basicConfig(stream=sys.stderr, level=log.WARNING, format=log_msg_format)
        logger = log.getLogger()
        logger.debug("Logger initiated")
        main(logger, cargs)
        logger.debug("Run completed - exit")
        log.shutdown()
    except Exception as exc:
        rc = 1
        if logger is not None:
            logger.error("Unrecoverable error: {}".format(str(exc)))
            logger.debug("=== TRACEBACK ===\n\n")
            buf = io.StringIO()
            trb.print_exc(file=buf)
            logger.error(buf.getvalue())
            logger.debug("Exit\n")
            log.shutdown()
        else:
            trb.print_exc()
    finally:
        sys.exit(rc)
